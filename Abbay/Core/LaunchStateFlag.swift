//
//  LaunchStateFlag.swift
//  Abbay
//

import Foundation

/// Whether the audio session was unavailable when last tried, shared with the Siri extension
/// through the App Group store. The store is injected; production uses `shared`.
struct LaunchStateFlag {
    static let key: String = "abbay.audioSessionUnavailable"

    static let shared = LaunchStateFlag()

    private let store: KeyValueStoring

    init(store: KeyValueStoring = AppGroup.store) {
        self.store = store
    }

    func markUnavailable() {
        store.set(true, forKey: Self.key)
    }

    func clear() {
        store.removeObject(forKey: Self.key)
    }

    func isUnavailable() -> Bool {
        store.object(forKey: Self.key) as? Bool ?? false
    }
}
