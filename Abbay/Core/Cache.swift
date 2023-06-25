//
//  Cache.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 24/06/23.
//

import Foundation

protocol CacheProtocol {
    associatedtype Value
    associatedtype Key: Hashable

    func put(_ value: Value, withKey key: Key)
    func getValue(forKey key: Key) -> Value?
    func removeValue(forKey key: Key)
    func getAllValues() -> [Value]?
}

final class Cache<Key: Hashable, Value>: CacheProtocol {
    private let cache = NSCache<WrappedKey, WrappedValue>()
    private let keyStorage = KeyStorage()

    func put(_ value: Value, withKey key: Key) {
        let value = WrappedValue(key: key, value: value)
        let key = WrappedKey(key: key)

        cache.setObject(value, forKey: key)
        keyStorage.put(value)
    }

    func getValue(forKey key: Key) -> Value? {
        let key = WrappedKey(key: key)
        return cache.object(forKey: key)?.value
    }

    func getAllValues() -> [Value]? {
        keyStorage.keys.compactMap { key in
            getValue(forKey: key)
        }
    }

    func removeValue(forKey key: Key) {
        let key = WrappedKey(key: key)
        cache.removeObject(forKey: key)
    }
}

// MARK: - Subscript
extension Cache {
    subscript(key: Key) -> Value? {
        get {
            getValue(forKey: key)
        }
        set {
            guard let value = newValue else {
                return removeValue(forKey: key)
            }
            put(value, withKey: key)
        }
    }
}

// MARK: - Helper classes
extension Cache {
    fileprivate final class WrappedKey: NSObject {
        let key: Key

        init(key: Key) {
            self.key = key
        }

        override var hash: Int {
            key.hashValue
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let value = object as? WrappedKey else {
                return false
            }
            return value.key == key
        }
    }

    fileprivate final class WrappedValue {
        let key: Key
        let value: Value

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    fileprivate final class KeyStorage: NSObject, NSCacheDelegate {
        var keys = Set<Key>()

        func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
            guard let object = obj as? WrappedValue else { return }
            keys.remove(object.key)
        }

        func put(_ value: WrappedValue) {
            keys.insert(value.key)
        }
    }
}

// MARK: - Persistency
extension Cache.WrappedValue: Codable where Key: Codable, Value: Codable {}

extension Cache where Key: Codable, Value: Codable {
    static var cacheExtension: String {
        ".cache"
    }

    static func load(
        withName name: String,
        using fileManager: FileManager = .default
    ) -> Cache {
        let fileURL = getFileURL(withName: name, using: fileManager)
        let decoder = JSONDecoder()
        let cache = Cache()
        guard let data = try? Data(contentsOf: fileURL),
              let values = try? decoder.decode([WrappedValue].self, from: data) else {
            return cache
        }
        for value in values {
            cache.put(value.value, withKey: value.key)
        }
        return cache
    }

    func save(
        withName name: String,
        using fileManager: FileManager = .default
    ) throws {
        let fileURL = Self.getFileURL(withName: name, using: fileManager)
        let values = keyStorage.keys.compactMap { key in
            let key = WrappedKey(key: key)
            return cache.object(forKey: key)
        }
        let data = try JSONEncoder().encode(values)
        try data.write(to: fileURL)
    }

    private static func getFileURL(
        withName name: String,
        using fileManager: FileManager = .default
    ) -> URL {
        let folderURLs = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )
        return folderURLs[0].appendingPathComponent(name + cacheExtension)
    }
}
