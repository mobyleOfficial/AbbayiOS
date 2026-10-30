//
//  AppSettings.swift
//  Abbay
//

import Foundation
import Observation

/// Where the player reads and writes a book's speed. A protocol so the player's tests (and its
/// default) need no settings at all.
protocol PlaybackSpeedStoring: AnyObject {
    /// The book's own speed, else the default for new books. Safe off the main thread: it reads
    /// the store, not the observable cache.
    func playbackSpeed(for url: URL?) -> Double
    /// Any thread.
    func setSpeed(_ speed: Double, for url: URL?)
}

/// Always normal speed and remembers nothing: `Player`'s default, for tests that don't care.
final class NormalPlaybackSpeed: PlaybackSpeedStoring {
    func playbackSpeed(for url: URL?) -> Double { PlaybackSpeed.normal }
    func setSpeed(_ speed: Double, for url: URL?) {}
}

/// Pushes settings that something outside SwiftUI consumes: the skip intervals (lock screen and
/// CarPlay, through `NowPlayingManager`) and the language (`AbbayBundle`).
protocol SettingsEffects {
    func apply(skipBackward: SkipInterval, skipForward: SkipInterval)
    func apply(language: AppLanguage)
    /// Read-along was turned off: the transcripts it made go with it.
    func clearReadAlong()
}

struct LiveSettingsEffects: SettingsEffects {
    func apply(skipBackward: SkipInterval, skipForward: SkipInterval) {
        NowPlayingManager.shared.setSkipIntervals(backward: skipBackward.seconds, forward: skipForward.seconds)
    }

    func apply(language: AppLanguage) {
        AbbayBundle.languageCode = language.languageCode
        NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
    }

    func clearReadAlong() {
        ReadAlongStore.shared.deleteAll()
    }
}

extension Notification.Name {
    /// Posted after the in-app language is applied to `AbbayBundle` (at launch and on every change
    /// in Settings). SwiftUI re-renders off `AppSettings` itself; this is for what lives outside
    /// it: CarPlay re-reads its strings (#152).
    static let appLanguageDidChange = Notification.Name("abbay.appLanguageDidChange")
}

/// The app's settings, persisted through the storage layer's `KeyValueStoring` and observable, so
/// the Settings screen, the player's buttons and the speed sheet follow every change.
///
/// Per-book speeds live here too, keyed by the book's URL (its identity, `AudioModel.url`, which
/// Core Data and the player use; never where a moved file resolves, #186), rather than as a new Core Data attribute: see the Settings PR for why. Mutations happen
/// on the main thread (UI and remote commands); `playbackSpeed(for:)` may be read from any thread.
@Observable
final class AppSettings: PlaybackSpeedStoring, BookSpeedRekeying {
    enum Key {
        static let skipBackward = "abbay.settings.skipBackward"
        static let skipForward = "abbay.settings.skipForward"
        static let defaultSpeed = "abbay.settings.defaultSpeed"
        static let bookSpeeds = "abbay.settings.bookSpeeds"
        static let cellularPreference = "abbay.settings.cellularPreference"
        static let language = "abbay.settings.language"
        static let readAlongEnabled = "abbay.settings.readAlong"
        static let readAlongShowsText = "abbay.settings.readAlongShowsText"
        static let readAlongLanguages = "abbay.settings.readAlongLanguages"
    }

    @ObservationIgnored private let store: KeyValueStoring
    @ObservationIgnored private let effects: SettingsEffects?

    var skipBackward: SkipInterval {
        didSet {
            store.set(skipBackward.rawValue, forKey: Key.skipBackward)
            applySkipIntervals()
        }
    }

    var skipForward: SkipInterval {
        didSet {
            store.set(skipForward.rawValue, forKey: Key.skipForward)
            applySkipIntervals()
        }
    }

    /// The speed of every book that has none of its own. Snapped on write.
    var defaultSpeed: Double {
        didSet {
            let snapped = PlaybackSpeed.snap(defaultSpeed)
            if snapped != defaultSpeed {
                defaultSpeed = snapped
                return
            }
            store.set(defaultSpeed, forKey: Key.defaultSpeed)
        }
    }

    var cellularPreference: CellularDownloadPreference {
        didSet { store.set(cellularPreference.rawValue, forKey: Key.cellularPreference) }
    }

    var language: AppLanguage {
        didSet {
            store.set(language.languageCode, forKey: Key.language)
            effects?.apply(language: language)
        }
    }

    /// Experimental read-along (#192). Off by default; turning it off deletes every transcript.
    var readAlongEnabled: Bool {
        didSet {
            store.set(readAlongEnabled, forKey: Key.readAlongEnabled)
            if !readAlongEnabled {
                effects?.clearReadAlong()
            }
        }
    }

    /// What the player's cover square last showed: the text (true) or the cover. False until the
    /// user flips it once, so turning the feature on changes nothing they can see.
    var readAlongShowsText: Bool {
        didSet { store.set(readAlongShowsText, forKey: Key.readAlongShowsText) }
    }

    /// Speeds set on a book, by URL string. The observable copy views read.
    private(set) var bookSpeeds: [String: Double]

    init(store: KeyValueStoring, effects: SettingsEffects? = nil) {
        self.store = store
        self.effects = effects
        skipBackward = (store.object(forKey: Key.skipBackward) as? Int).flatMap(SkipInterval.init) ?? .standard
        skipForward = (store.object(forKey: Key.skipForward) as? Int).flatMap(SkipInterval.init) ?? .standard
        defaultSpeed = Self.storedDefaultSpeed(in: store)
        cellularPreference = (store.object(forKey: Key.cellularPreference) as? String)
            .flatMap(CellularDownloadPreference.init) ?? .ask
        language = (store.object(forKey: Key.language) as? String).flatMap(AppLanguage.init(languageCode:)) ?? .system
        readAlongEnabled = store.object(forKey: Key.readAlongEnabled) as? Bool ?? false
        readAlongShowsText = store.object(forKey: Key.readAlongShowsText) as? Bool ?? false
        bookSpeeds = Self.storedBookSpeeds(in: store)
        applySkipIntervals()
        effects?.apply(language: language)
    }

    // MARK: - Per-book speed

    /// For views: observable, so a speed change from anywhere re-renders the reader.
    func speed(for url: URL?) -> Double {
        guard let key = url?.absoluteString else { return defaultSpeed }
        return bookSpeeds[key] ?? defaultSpeed
    }

    func playbackSpeed(for url: URL?) -> Double {
        let fallback = Self.storedDefaultSpeed(in: store)
        guard let key = url?.absoluteString else { return fallback }
        return Self.storedBookSpeeds(in: store)[key] ?? fallback
    }

    /// Writes the store at once, so the player's next read agrees; the observable copy views read
    /// is updated on the main thread (a Siri play can load a book off it).
    func setSpeed(_ speed: Double, for url: URL?) {
        guard let key = url?.absoluteString else { return }
        let speed = PlaybackSpeed.snap(speed)
        var stored = Self.storedBookSpeeds(in: store)
        guard stored[key] != speed else { return }
        stored[key] = speed
        store.set(stored, forKey: Key.bookSpeeds)
        Self.onMain { [weak self] in
            guard let self else { return }
            var speeds = bookSpeeds
            speeds[key] = speed
            bookSpeeds = speeds
        }
    }

    /// A speed saved under the URL a moved book's file resolved to, before #186 keyed books by
    /// their row: keep it under the row's URL (a speed already there wins) and drop the old key.
    /// Writes the store at once; the observable copy follows on the main thread, like `setSpeed`.
    func moveSpeed(from oldURL: URL, to newURL: URL) {
        let oldKey = oldURL.absoluteString
        let newKey = newURL.absoluteString
        var stored = Self.storedBookSpeeds(in: store)
        guard let speed = stored.removeValue(forKey: oldKey) else { return }
        if stored[newKey] == nil {
            stored[newKey] = speed
        }
        store.set(stored, forKey: Key.bookSpeeds)
        Self.onMain { [weak self] in
            guard let self else { return }
            var speeds = bookSpeeds
            speeds[oldKey] = nil
            speeds[newKey] = stored[newKey]
            bookSpeeds = speeds
        }
    }

    /// The book left the library: drop its speed with it. Main thread.
    func forgetSpeed(for url: URL?) {
        guard let key = url?.absoluteString else { return }
        var stored = Self.storedBookSpeeds(in: store)
        if stored.removeValue(forKey: key) != nil {
            store.set(stored, forKey: Key.bookSpeeds)
        }
        if bookSpeeds[key] != nil {
            var speeds = bookSpeeds
            speeds[key] = nil
            bookSpeeds = speeds
        }
    }

    // MARK: - Per-book read-along language

    /// The language the book is read along in: a locale id (`pt-BR`, once the user picked or
    /// detection settled) or a bare code hint (`pt`, from LibriVox's listing). Read from the
    /// store, not an observable copy: only the transcriber and the language sheet ask.
    func readAlongLanguage(for url: URL?) -> String? {
        guard let key = url?.absoluteString else { return nil }
        return Self.storedReadAlongLanguages(in: store)[key]
    }

    /// nil clears it. Main thread, like the other writes.
    func setReadAlongLanguage(_ language: String?, for url: URL?) {
        guard let key = url?.absoluteString else { return }
        var stored = Self.storedReadAlongLanguages(in: store)
        guard stored[key] != language else { return }
        stored[key] = language
        store.set(stored, forKey: Key.readAlongLanguages)
    }

    /// The book left the library: drop its language with it (its transcript file goes through
    /// `ReadAlongStore`). Main thread.
    func forgetReadAlong(for url: URL?) {
        setReadAlongLanguage(nil, for: url)
    }

    // MARK: - Private

    private func applySkipIntervals() {
        effects?.apply(skipBackward: skipBackward, skipForward: skipForward)
    }

    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private static func storedDefaultSpeed(in store: KeyValueStoring) -> Double {
        (store.object(forKey: Key.defaultSpeed) as? Double).map(PlaybackSpeed.snap) ?? PlaybackSpeed.normal
    }

    private static func storedReadAlongLanguages(in store: KeyValueStoring) -> [String: String] {
        store.object(forKey: Key.readAlongLanguages) as? [String: String] ?? [:]
    }

    private static func storedBookSpeeds(in store: KeyValueStoring) -> [String: Double] {
        store.object(forKey: Key.bookSpeeds) as? [String: Double] ?? [:]
    }
}
