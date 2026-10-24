//
//  AppSettingsTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// `AppSettings` persists through the injected `KeyValueStoring`, so a second instance over the
/// same store reads back what the first wrote, and it pushes the skip intervals and the language
/// to their consumers through `SettingsEffects`.
final class AppSettingsTests: XCTestCase {
    private final class RecordingEffects: SettingsEffects {
        var skipIntervals: [(back: SkipInterval, forward: SkipInterval)] = []
        var languages: [AppLanguage] = []

        func apply(skipBackward: SkipInterval, skipForward: SkipInterval) {
            skipIntervals.append((skipBackward, skipForward))
        }

        func apply(language: AppLanguage) {
            languages.append(language)
        }
    }

    private let bookURL = URL(string: "file:///settings/book.m4b")
    private let otherURL = URL(string: "librivox://book/moby")

    // MARK: - Defaults

    func test_freshStore_hasTheDefaults() {
        let sut = AppSettings(store: InMemoryKeyValueStore())

        XCTAssertEqual(sut.skipBackward, .fifteen)
        XCTAssertEqual(sut.skipForward, .fifteen)
        XCTAssertEqual(sut.defaultSpeed, 1)
        XCTAssertEqual(sut.cellularPreference, .ask)
        XCTAssertEqual(sut.language, .system)
        XCTAssertEqual(sut.speed(for: bookURL), 1, "a book never set uses the default speed")
    }

    /// Garbage left in the store (an older build, a hand edit) falls back to the default.
    func test_unknownStoredValues_fallBackToTheDefaults() {
        let store = InMemoryKeyValueStore([
            AppSettings.Key.skipBackward: 7,
            AppSettings.Key.cellularPreference: "sometimes",
            AppSettings.Key.language: "klingon",
            AppSettings.Key.defaultSpeed: 99.0
        ])

        let sut = AppSettings(store: store)

        XCTAssertEqual(sut.skipBackward, .fifteen)
        XCTAssertEqual(sut.cellularPreference, .ask)
        XCTAssertEqual(sut.language, .system)
        XCTAssertEqual(sut.defaultSpeed, PlaybackSpeed.maximum, "an out-of-range speed is clamped")
    }

    // MARK: - Persistence

    func test_changes_persistAcrossInstances() {
        let store = InMemoryKeyValueStore()
        let first = AppSettings(store: store)

        first.skipBackward = .ten
        first.skipForward = .thirty
        first.defaultSpeed = 1.5
        first.cellularPreference = .wifiOnly
        first.language = .portuguese

        let second = AppSettings(store: store)
        XCTAssertEqual(second.skipBackward, .ten)
        XCTAssertEqual(second.skipForward, .thirty)
        XCTAssertEqual(second.defaultSpeed, 1.5)
        XCTAssertEqual(second.cellularPreference, .wifiOnly)
        XCTAssertEqual(second.language, .portuguese)
    }

    func test_defaultSpeed_isSnappedToTheStep() {
        let sut = AppSettings(store: InMemoryKeyValueStore())

        sut.defaultSpeed = 1.2345

        XCTAssertEqual(sut.defaultSpeed, 1.25)
    }

    // MARK: - Per-book speed

    func test_bookSpeed_isPerBook_andPersists() {
        let store = InMemoryKeyValueStore()
        let sut = AppSettings(store: store)

        sut.setSpeed(1.75, for: bookURL)

        XCTAssertEqual(sut.speed(for: bookURL), 1.75)
        XCTAssertEqual(sut.speed(for: otherURL), 1, "another book keeps the default")
        XCTAssertEqual(AppSettings(store: store).speed(for: bookURL), 1.75)
        XCTAssertEqual(AppSettings(store: store).playbackSpeed(for: bookURL), 1.75, "the player's read agrees")
    }

    /// The default applies to books that have no speed of their own, including ones already in the
    /// library; a book's own speed wins over it.
    func test_defaultSpeed_appliesOnlyToBooksWithoutTheirOwn() {
        let sut = AppSettings(store: InMemoryKeyValueStore())
        sut.setSpeed(0.8, for: bookURL)

        sut.defaultSpeed = 2

        XCTAssertEqual(sut.speed(for: bookURL), 0.8)
        XCTAssertEqual(sut.speed(for: otherURL), 2)
        XCTAssertEqual(sut.playbackSpeed(for: otherURL), 2)
    }

    func test_forgetSpeed_dropsTheBooksEntry() {
        let store = InMemoryKeyValueStore()
        let sut = AppSettings(store: store)
        sut.setSpeed(2.5, for: bookURL)

        sut.forgetSpeed(for: bookURL)

        XCTAssertEqual(sut.speed(for: bookURL), 1)
        XCTAssertEqual(AppSettings(store: store).speed(for: bookURL), 1)
    }

    func test_deletingABook_forgetsItsSpeed() {
        final class NoopRepository: DeleteAudioRepositoryProtocol {
            func execute(url: URL?) {}
        }
        let settings = AppSettings(store: InMemoryKeyValueStore())
        settings.setSpeed(2, for: bookURL)
        let sut = DeleteAudioUseCase(
            repository: NoopRepository(),
            removeDownloads: { _ in },
            forgetSettings: settings.forgetSpeed(for:)
        )

        sut.execute(AudioModel(url: bookURL))

        XCTAssertEqual(settings.speed(for: bookURL), 1, "a re-added book starts from the default again")
    }

    func test_bookWithoutURL_hasTheDefaultSpeed_andIgnoresWrites() {
        let sut = AppSettings(store: InMemoryKeyValueStore())

        sut.setSpeed(2, for: nil)

        XCTAssertEqual(sut.speed(for: nil), 1)
    }

    // MARK: - Effects

    func test_init_appliesTheStoredSkipIntervalsAndLanguage() {
        let store = InMemoryKeyValueStore([
            AppSettings.Key.skipBackward: 30,
            AppSettings.Key.skipForward: 45,
            AppSettings.Key.language: "pt-BR"
        ])
        let effects = RecordingEffects()

        _ = AppSettings(store: store, effects: effects)

        XCTAssertEqual(effects.skipIntervals.last?.back, .thirty)
        XCTAssertEqual(effects.skipIntervals.last?.forward, .fortyFive)
        XCTAssertEqual(effects.languages, [.portuguese])
    }

    func test_changingASkipInterval_reappliesBoth() {
        let effects = RecordingEffects()
        let sut = AppSettings(store: InMemoryKeyValueStore(), effects: effects)

        sut.skipForward = .thirty

        XCTAssertEqual(effects.skipIntervals.count, 2)
        XCTAssertEqual(effects.skipIntervals.last?.back, .fifteen)
        XCTAssertEqual(effects.skipIntervals.last?.forward, .thirty)
    }

    func test_changingTheLanguage_appliesIt() {
        let effects = RecordingEffects()
        let sut = AppSettings(store: InMemoryKeyValueStore(), effects: effects)

        sut.language = .english

        XCTAssertEqual(effects.languages, [.system, .english])
    }
}
