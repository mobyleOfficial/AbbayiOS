//
//  KeyValueStore.swift
//  Abbay
//

import Foundation

/// The small key-value half of the storage layer (Core Data holds the library): the app's
/// preferences, and the App Group values the Siri extension shares (`AppGroup.store`). Injected
/// wherever it is read, so tests swap in `InMemoryKeyValueStore` instead of reaching into
/// `UserDefaults`. Values are property-list types. Foundation only, so the extension compiles it.
protocol KeyValueStoring: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    /// Writes pending changes out now rather than on the store's own schedule. Only the Siri
    /// diagnostics trail needs it.
    @discardableResult
    func synchronize() -> Bool
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

    /// Nothing to write out: the values never leave the process.
    func synchronize() -> Bool {
        true
    }
}
