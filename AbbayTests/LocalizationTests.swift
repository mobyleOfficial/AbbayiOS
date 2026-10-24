//
//  LocalizationTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The `Localizable` layer had no tests. Every key ships in two languages, and nothing checked
/// that either language actually resolves or that the format strings take their arguments.
final class LocalizationTests: XCTestCase {
    private let allKeys: [Localizable] = [
        .libraryTitle,
        .emptyLibraryTitle,
        .chapterSelectionTitle,
        .chapterCount,
        .delete,
        .addMenu,
        .importFile,
        .browseFreeAudiobooks,
        .importAFile,
        .popularOnLibriVox,
        .librivoxSearchPrompt,
        .searchTitle,
        .searchOffline,
        .searchFailed,
        .noResults,
        .downloadedTag,
        .downloadPaused,
        .downloadingProgress,
        .download,
        .play,
        .chaptersCount,
        .librivoxCredit,
        .more,
        .largeDownloadTitle,
        .largeDownloadMessage,
        .continueDownload,
        .waitForWiFi,
        .waiting,
        .chapterDownloadFailed,
        .detailsFailed,
        .retry,
        .rowChapter,
        .rowTimeLeft,
        .libraryTab,
        .searchTab,
        .librarySearchPrompt,
        .closePlayer,
        .miniPlayerSubtitle,
        .chapterProgress,
        .openPlayer,
        .nextChapterAction,
        .restartChapterAction,
        .carPlayEmptyLibraryTitle,
        .carPlayEmptyLibrarySubtitle,
        .noticeImportFailedOne,
        .noticeImportFailedMany,
        .noticeImportFailedMore,
        .noticeFileMissing,
        .noticePlaybackFailed,
        .noticeAudioUnavailable,
        .noticeStreamingOffline,
        .noticeChapterFailed,
        .noticeSaveFailed,
        .noticeDismiss,
        .settingsTitle,
        .done,
        .settingsPlayback,
        .defaultSpeed,
        .defaultSpeedFooter,
        .skipBack,
        .skipForward,
        .skipSeconds,
        .skipFooter,
        .settingsDownloads,
        .cellularDownloads,
        .cellularAsk,
        .cellularAlways,
        .cellularWifiOnly,
        .cellularFooter,
        .spaceUsed,
        .calculating,
        .deleteFinished,
        .deleteFinishedFooter,
        .deleteFinishedNone,
        .deleteFinishedTitle,
        .deleteFinishedMessage,
        .cancel,
        .settingsLanguage,
        .languageSystem,
        .languageFooter,
        .settingsAbout,
        .privacyPolicy,
        .version,
        .librivoxAbout,
        .openSourceLicenses,
        .licensesBody,
        .licensesContent,
        .siriAudioStatus,
        .audioStatusOK,
        .audioStatusUnavailable,
        .audioStatusOKDetail,
        .audioStatusUnavailableDetail,
        .playbackSpeed,
        .speedDecrease,
        .speedIncrease,
        .speedPresets,
        .speedSetDefault,
        .speedIsDefault,
        .skipBackAction,
        .skipForwardAction
    ]

    /// User-facing prose, which must be translated. Adding a new string of this kind without a
    /// pt-BR entry should fail here.
    private let proseKeys: [Localizable] = [
        .libraryTitle,
        .emptyLibraryTitle,
        .chapterSelectionTitle,
        .delete,
        .addMenu,
        .importFile,
        .browseFreeAudiobooks,
        .importAFile,
        .popularOnLibriVox,
        .librivoxSearchPrompt,
        .searchTitle,
        .searchOffline,
        .searchFailed,
        .noResults,
        .downloadedTag,
        .downloadPaused,
        .downloadingProgress,
        .download,
        .play,
        .chaptersCount,
        .librivoxCredit,
        .more,
        .largeDownloadTitle,
        .largeDownloadMessage,
        .continueDownload,
        .waitForWiFi,
        .waiting,
        .chapterDownloadFailed,
        .detailsFailed,
        .retry,
        .rowChapter,
        .rowTimeLeft,
        .libraryTab,
        .searchTab,
        .librarySearchPrompt,
        .closePlayer,
        .miniPlayerSubtitle,
        .chapterProgress,
        .openPlayer,
        .nextChapterAction,
        .restartChapterAction,
        .carPlayEmptyLibraryTitle,
        .carPlayEmptyLibrarySubtitle,
        .noticeImportFailedOne,
        .noticeImportFailedMany,
        .noticeImportFailedMore,
        .noticeFileMissing,
        .noticePlaybackFailed,
        .noticeAudioUnavailable,
        .noticeStreamingOffline,
        .noticeChapterFailed,
        .noticeSaveFailed,
        .noticeDismiss,
        .settingsTitle,
        .done,
        .settingsPlayback,
        .defaultSpeed,
        .defaultSpeedFooter,
        .skipBack,
        .skipForward,
        .skipSeconds,
        .skipFooter,
        .cellularDownloads,
        .cellularAsk,
        .cellularAlways,
        .cellularWifiOnly,
        .cellularFooter,
        .spaceUsed,
        .calculating,
        .deleteFinished,
        .deleteFinishedFooter,
        .deleteFinishedNone,
        .deleteFinishedTitle,
        .deleteFinishedMessage,
        .cancel,
        .settingsLanguage,
        .languageSystem,
        .languageFooter,
        .settingsAbout,
        .privacyPolicy,
        .version,
        .librivoxAbout,
        .openSourceLicenses,
        .licensesBody,
        .licensesContent,
        .siriAudioStatus,
        .audioStatusOK,
        .audioStatusUnavailable,
        .audioStatusOKDetail,
        .audioStatusUnavailableDetail,
        .playbackSpeed,
        .speedDecrease,
        .speedIncrease,
        .speedPresets,
        .speedSetDefault,
        .speedIsDefault,
        .skipBackAction,
        .skipForwardAction
    ]

    /// Format-only strings (`%d/%d`). They carry no language, so they deliberately ship a single
    /// entry and fall back to the base language rather than being duplicated per locale.
    private let formatOnlyKeys: [Localizable] = [.chapterCount]

    /// The test host is the real app, which applies the stored in-app language at launch. Every
    /// assertion here is about the bundle's own languages, so start from no override.
    override func setUpWithError() throws {
        try super.setUpWithError()
        AbbayBundle.languageCode = nil
    }

    override func tearDownWithError() throws {
        AbbayBundle.value.unsetLocalizedLanguage()
        AbbayBundle.languageCode = nil
        try super.tearDownWithError()
    }

    // MARK: - In-app language (Settings)

    func test_inAppLanguageOverride_readsThatLanguage_andNilFollowsTheDevice() {
        let deviceValue = Localizable.settingsTitle.localized

        AbbayBundle.languageCode = "pt-BR"
        XCTAssertEqual(Localizable.settingsTitle.localized, "Ajustes")
        XCTAssertEqual(Localizable.skipSeconds.localized(with: 30), "30 segundos")
        XCTAssertEqual(AbbayBundle.locale.identifier, "pt-BR")

        AbbayBundle.languageCode = "en"
        XCTAssertEqual(Localizable.settingsTitle.localized, "Settings")

        AbbayBundle.languageCode = nil
        XCTAssertEqual(Localizable.settingsTitle.localized, deviceValue)
    }

    /// Choosing a language in Settings applies it to the bundle at once, with no relaunch.
    func test_choosingALanguage_inSettings_switchesTheStrings() {
        let settings = AppSettings(store: InMemoryKeyValueStore(), effects: LiveSettingsEffects())

        settings.language = .portuguese
        XCTAssertEqual(Localizable.playbackSpeed.localized, "Velocidade de reprodução")

        settings.language = .english
        XCTAssertEqual(Localizable.playbackSpeed.localized, "Playback speed")
    }

    // MARK: - Resolution

    func test_everyKeyResolvesToSomethingOtherThanItsOwnName() {
        for key in allKeys {
            let value = key.localized
            XCTAssertFalse(value.isEmpty, "\(key.rawValue) resolved to an empty string")
            XCTAssertNotEqual(
                value,
                key.rawValue,
                "\(key.rawValue) resolved to its own key, so the string is missing from the table"
            )
        }
    }

    /// The bundle swizzle forwards straight to `pt-BR.lproj` with no base-language fallback, so a
    /// key with no pt-BR entry resolves to its own name. That makes this a genuine check that the
    /// translation exists rather than that the fallback works.
    func test_proseKeysAreTranslatedToPortuguese() {
        var english: [String: String] = [:]
        for key in proseKeys {
            english[key.rawValue] = key.localized
        }

        XCTAssertTrue(
            AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"),
            "pt-BR.lproj is not in the app bundle; the xcstrings table did not compile"
        )

        for key in proseKeys {
            let translated = key.localized
            XCTAssertFalse(translated.isEmpty, "\(key.rawValue) is empty in pt-BR")
            XCTAssertNotEqual(translated, key.rawValue, "\(key.rawValue) has no pt-BR entry")
            XCTAssertNotEqual(
                translated,
                english[key.rawValue],
                "\(key.rawValue) is identical in both languages, so it is probably untranslated"
            )
        }
    }

    /// Pins the decision that this one is shared rather than translated, so nobody "fixes" the
    /// gap by pasting `%d/%d` into every locale.
    func test_formatOnlyKeysCarryTheirSpecifiersAndAreNotTranslated() {
        XCTAssertEqual(Localizable.chapterCount.localized, "%d/%d")

        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        for key in formatOnlyKeys {
            XCTAssertEqual(
                key.localized,
                key.rawValue,
                "\(key.rawValue) now has a pt-BR entry; decide whether that is intended"
            )
        }
    }

    // MARK: - Format strings

    /// `localized(with:)` passes a variadic list through to `String(format:)`.
    func test_chapterCountFormatsBothArguments() {
        let formatted = Localizable.chapterCount.localized(with: 2, 7)

        XCTAssertTrue(formatted.contains("2"), "chapter number missing from \"\(formatted)\"")
        XCTAssertTrue(formatted.contains("7"), "chapter total missing from \"\(formatted)\"")
    }

    func test_rowDetailFormatsTakeTheirArguments() {
        XCTAssertEqual(Localizable.rowChapter.localized(with: 2, 7), "Ch 2/7")
        XCTAssertEqual(Localizable.rowTimeLeft.localized(with: "3m", 3), "3m left")
    }

    func test_miniPlayerSubtitleFormatsItsArguments() {
        XCTAssertEqual(Localizable.miniPlayerSubtitle.localized(with: 35, "12 min", 12), "Chapter 35 · 12 min left")

        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        XCTAssertEqual(
            Localizable.miniPlayerSubtitle.localized(with: 35, "12 min", 12),
            "Capítulo 35 · 12 min restantes"
        )
    }

    // MARK: - Plurals

    /// English "left" does not inflect, so the count is taken and ignored.
    func test_timeLeftStrings_inEnglish_readTheSameInSingularAndPlural() {
        XCTAssertEqual(Localizable.rowTimeLeft.localized(with: "1 min", 1), "1 min left")
        XCTAssertEqual(Localizable.rowTimeLeft.localized(with: "2 min", 2), "2 min left")
        XCTAssertEqual(Localizable.miniPlayerSubtitle.localized(with: 2, "1 min", 1), "Chapter 2 · 1 min left")
        XCTAssertEqual(Localizable.miniPlayerSubtitle.localized(with: 2, "2 min", 2), "Chapter 2 · 2 min left")
    }

    /// pt-BR reads "%@ restante(s)", not "faltam %@", which is wrong at one minute ("faltam 1 min"),
    /// and "restante" agrees with the count (#124).
    func test_timeLeftStrings_inPortuguese_agreeWithTheCount() {
        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        XCTAssertEqual(Localizable.rowTimeLeft.localized(with: "1 min", 1), "1 min restante")
        XCTAssertEqual(Localizable.rowTimeLeft.localized(with: "2 min", 2), "2 min restantes")
        XCTAssertEqual(Localizable.miniPlayerSubtitle.localized(with: 2, "1 min", 1), "Capítulo 2 · 1 min restante")
        XCTAssertEqual(Localizable.miniPlayerSubtitle.localized(with: 2, "2 min", 2), "Capítulo 2 · 2 min restantes")
        XCTAssertEqual(Localizable.chapterProgress.localized, "Progresso do capítulo")
    }

    // MARK: - Units follow the app language

    /// The duration formatters take their locale from here, so it must track the in-app language
    /// override, not the device locale.
    func test_appLocale_followsTheInAppLanguage() {
        XCTAssertEqual(AbbayBundle.locale.identifier, "en")

        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        XCTAssertEqual(AbbayBundle.locale.identifier, "pt-BR")
    }

    /// One unit reads as singular, anything more as plural, and the units ("hr" / "h e") are in
    /// the same language as the sentence around them.
    func test_miniPlayerSubtitle_formatsUnitsInTheAppLanguage() {
        let book = AudioModel(duration: 10_000, chapters: [ChapterModel(startTime: 0, duration: 10_000)])

        XCTAssertEqual(MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 9940), "Chapter 1 · 1 min left")
        XCTAssertEqual(
            MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 2740),
            "Chapter 1 · 2 hr, 1 min left"
        )

        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        XCTAssertEqual(
            MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 9940),
            "Capítulo 1 · 1 min restante"
        )
        XCTAssertEqual(
            MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 9880),
            "Capítulo 1 · 2 min restantes"
        )
        XCTAssertEqual(
            MiniPlayerActions.subtitle(book: book, chapter: 0, bookTime: 2740),
            "Capítulo 1 · 2 h e 1 min restantes"
        )
    }

    func test_rowDetailLine_formatsUnitsInTheAppLanguage() {
        let book = AudioModel(duration: 3600)

        XCTAssertEqual(MediaView.detailLine(book: book, chapterIndex: 0, bookTime: 0), "1h left")
        XCTAssertEqual(MediaView.detailLine(book: book, chapterIndex: 0, bookTime: 3510), "1m 30s left")

        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        XCTAssertEqual(MediaView.detailLine(book: book, chapterIndex: 0, bookTime: 0), "1h restante")
        XCTAssertEqual(MediaView.detailLine(book: book, chapterIndex: 0, bookTime: 3540), "1min restante")
        XCTAssertEqual(MediaView.detailLine(book: book, chapterIndex: 0, bookTime: 3510), "1min 30s restantes")
    }
}
