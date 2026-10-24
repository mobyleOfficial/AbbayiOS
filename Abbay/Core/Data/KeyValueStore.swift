//
//  KeyValueStore.swift
//  Abbay
//

import Foundation

/// The small key-value half of the storage layer, for preferences (Core Data holds the library).
/// Injected wherever it is read, so tests swap in `InMemoryKeyValueStore` instead of reaching into
/// `UserDefaults`. Values are property-list types.
protocol KeyValueStoring: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: KeyValueStoring {}

/// A store that lives for the process only: unit tests, and UI tests launched with
/// `-resetSettings`. Locked, because the player can read it off the main thread (a Siri play).
final class InMemoryKeyValueStore: KeyValueStoring {
    private var values: [String: Any]
    private let lock = NSLock()

    init(_ values: [String: Any] = [:]) {
        self.values = values
    }

    func object(forKey key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func set(_ value: Any?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func removeObject(forKey key: String) {
        set(nil, forKey: key)
    }
}
