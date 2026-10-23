//
//  CatalogCache.swift
//  Abbay
//

import Foundation

/// A small file-based JSON cache for catalog responses, one file per key.
///
/// It lives in Caches, so the system may purge it and it is never backed up. Every entry keeps the
/// time it was stored, and each reader decides what "fresh" means, so a stale entry can still be
/// shown when the network fails. Failures to read or write are ignored: the cache only saves time.
final class CatalogCache {
    struct Hit<Value> {
        let value: Value
        let storedAt: Date
        /// Younger than the `maxAge` the reader asked for.
        let isFresh: Bool
    }

    private struct Entry<Value: Codable>: Codable {
        let storedAt: Date
        let value: Value
    }

    static let shared = CatalogCache(directory: defaultDirectory)

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LibriVoxCatalog", isDirectory: true)
    }

    let directory: URL
    private let now: () -> Date
    private let lock = NSLock()

    init(directory: URL, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.now = now
    }

    /// The entry whether fresh or not; nil when there is none or it can't be decoded.
    func read<Value: Codable>(_ type: Value.Type, key: String, maxAge: TimeInterval) -> Hit<Value>? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let entry = try? JSONDecoder().decode(Entry<Value>.self, from: data)
        else { return nil }
        let age = now().timeIntervalSince(entry.storedAt)
        return Hit(value: entry.value, storedAt: entry.storedAt, isFresh: age < maxAge)
    }

    func write<Value: Codable>(_ value: Value, key: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(Entry(storedAt: now(), value: value)) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    func remove(key: String) {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    /// Keys may hold any character, so the file name is the key percent-encoded.
    private func fileURL(for key: String) -> URL {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_")
        let name = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }
}
