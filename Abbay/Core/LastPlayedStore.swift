//
//  LastPlayedStore.swift
//  Abbay
//

import Foundation

/// Persists the URL of the most-recently-played audiobook so that
/// Siri's "Play in Abbay" / "Resume Abbay" intents can resume it.
///
/// Single-process v1; `UserDefaults.standard`. Phase-2 migration to
/// App Group `UserDefaults` is documented in the design spec.
enum LastPlayedStore {
    private static let lastPlayedKey = "abbay.lastPlayedAudioURL"

    /// Injection point for tests. Production reads/writes `.standard`.
    static var defaults: UserDefaults = .standard

    static func save(url: URL?) {
        defaults.set(url?.absoluteString, forKey: lastPlayedKey)
    }

    static func lastPlayedURL() -> URL? {
        guard let string = defaults.string(forKey: lastPlayedKey) else { return nil }
        return URL(string: string)
    }
}
