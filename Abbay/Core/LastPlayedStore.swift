//
//  LastPlayedStore.swift
//  Abbay
//

import Foundation

/// Persists the URL of the most-recently-played audiobook so that
/// Siri's "Play in Abbay" / "Resume Abbay" intents can resume it.
///
/// Phase 2: storage moved to the App Group store so the `AbbayIntents`
/// extension can read the same value cross-process. `legacyStore` is
/// consulted on read (and seeded on write) to migrate phase-1 installs
/// whose value still lives in `.standard`.
///
/// Both stores are injected. Production uses `shared` (the App Group and
/// `.standard`); code the system builds itself reaches it through
/// `DependencyContainer.lastPlayed`.
struct LastPlayedStore {
    /// Public so `AppDelegateSeeder`, `IntentRouter`, and the extension can reference it.
    static let key: String = "abbay.lastPlayedAudioURL"

    static let shared = LastPlayedStore()

    private let store: KeyValueStoring
    /// Source for one-time seed migration from phase-1 storage.
    private let legacyStore: KeyValueStoring

    init(store: KeyValueStoring = AppGroup.store, legacyStore: KeyValueStoring = UserDefaults.standard) {
        self.store = store
        self.legacyStore = legacyStore
    }

    func save(url: URL?) {
        guard let url = url else {
            // Clear BOTH stores. The phase-1 fallback would otherwise resurface a stale
            // URL on the next read (re-introducing the stuck-state loop the callers are
            // explicitly trying to break).
            store.removeObject(forKey: Self.key)
            legacyStore.removeObject(forKey: Self.key)
            return
        }
        // Seed-then-write: if AppGroup empty AND .standard has value, copy first
        if store.object(forKey: Self.key) as? String == nil,
           let legacyValue = legacyStore.object(forKey: Self.key) as? String {
            store.set(legacyValue, forKey: Self.key)
        }
        store.set(url.absoluteString, forKey: Self.key)
    }

    func lastPlayedURL() -> URL? {
        if let value = store.object(forKey: Self.key) as? String {
            return URL(string: value)
        }
        if let legacyValue = legacyStore.object(forKey: Self.key) as? String {
            return URL(string: legacyValue)
        }
        return nil
    }
}
