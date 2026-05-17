//
//  LastPlayedStore.swift
//  Abbay
//

import Foundation

/// Persists the URL of the most-recently-played audiobook so that
/// Siri's "Play in Abbay" / "Resume Abbay" intents can resume it.
///
/// Phase 2: storage moved to the App Group `UserDefaults` so the
/// `AbbayIntents` extension can read the same value cross-process.
/// `standardFallback` is consulted on read (and seeded on write)
/// to migrate phase-1 installs whose value still lives in `.standard`.
enum LastPlayedStore {
    /// Public so `AppDelegateSeeder`, `IntentRouter`, and the extension can reference it.
    static let key: String = "abbay.lastPlayedAudioURL"

    /// Injection point for tests. Production reads/writes `AppGroup.defaults`.
    static var defaults: UserDefaults = AppGroup.defaults

    /// Source for one-time seed migration from phase-1 storage.
    static var standardFallback: UserDefaults = .standard

    static func save(url: URL?) {
        guard let url = url else {
            defaults.removeObject(forKey: key)
            return
        }
        // Seed-then-write: if AppGroup empty AND .standard has value, copy first
        if defaults.string(forKey: key) == nil,
           let standardValue = standardFallback.string(forKey: key) {
            defaults.set(standardValue, forKey: key)
        }
        defaults.set(url.absoluteString, forKey: key)
    }

    static func lastPlayedURL() -> URL? {
        if let value = defaults.string(forKey: key) {
            return URL(string: value)
        }
        if let standardValue = standardFallback.string(forKey: key) {
            return URL(string: standardValue)
        }
        return nil
    }
}
