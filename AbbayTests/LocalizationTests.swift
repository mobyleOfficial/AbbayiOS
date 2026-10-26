//
//  LocalizationTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The library grid's keys (#166 G3): every one is prose, translated in both languages. Outside the
/// test type, which is at its length limit.
private let libraryGridKeys: [Localizable] = [
    .libraryContinue, .libraryAllBooks, .resume, .rowNew, .rowFinished, .nowPlaying,
    .emptyLibraryMessage, .noResultsFor, .noResultsHint
]

/// Every key, for the checks that each one resolves. At file scope to keep the test type short.
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
    .lowDataModeWaiting,
    .cellularHoldWaiting,
    .hotspotHoldWaiting,
    .downloadingHeld,
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
    .noChaptersTitle,
    .noChaptersMessage,
    .chapterFinished,
    .chapterCurrent,
    .chaptersTitle,
    .chapterPosition,
    .closeChapters,
    .pause,
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
    .aboutDeveloper,
    .developerBody,
    .developerLinkedIn,
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
] + libraryGridKeys

/// The `Localizable` layer had no tests. Every key ships in two languages, and nothing checked
/// that either language actually resolves or that the format strings take their arguments.
final class LocalizationTests: XCTestCase {
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
        .lowDataModeWaiting,
        .cellularHoldWaiting,
        .hotspotHoldWaiting,
        .downloadingHeld,
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
        .noChaptersTitle,
        .noChaptersMessage,
        .chapterFinished,
        .chapterCurrent,
        .chaptersTitle,
        .chapterPosition,
        .closeChapters,
        .pause,
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
        .aboutDeveloper,
        .developerBody,
        .developerLinkedIn,
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
    ] + libraryGridKeys

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
            english[key.rawValue] = key.comparableText
        }

        XCTAssertTrue(
            AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"),
            "pt-BR.lproj is not in the app bundle; the xcstrings table did not compile"
        )

        for key in proseKeys {
            let translated = key.comparableText
            XCTAssertFalse(translated.isEmpty, "\(key.rawValue) is empty in pt-BR")
            XCTAssertNotEqual(translated, key.rawValue, "\(key.rawValue) has no pt-BR entry")
            XCTAssertNotEqual(
                translated,
                english[key.rawValue],
                "\(key.rawValue) is identical in both languages, so it is probably untranslated"
            )
        }
    }

    /// A chapter's download status sits between its title and its duration, on one line. pt-BR
    /// "Falhou · Tentar de novo" wrapped and squeezed the title on an iPhone SE (#148), so every
    /// status stays as short as "Aguardando" plus a word, in both languages.
    func test_chapterStatusesStayShortInBothLanguages() {
        let statuses: [Localizable] = [.waiting, .chapterDownloadFailed]
        let limit = 16
        for language in ["en", "pt-BR"] {
            XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: language))
            for key in statuses {
                XCTAssertLessThanOrEqual(key.localized.count, limit, "\(language) \(key.rawValue): \(key.localized)")
            }
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
}

/// Download holds (#171): the Library ring's label.
extension LocalizationTests {
    /// The ring of a held download: its percentage, then why.
    func test_downloadingHeldFormatsThePercentAndTheReason() {
        XCTAssertEqual(
            Localizable.downloadingHeld.localized(with: 33, Localizable.cellularHoldWaiting.localized),
            "Downloading, 33%. Waiting for Wi-Fi: on cellular"
        )

        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        XCTAssertEqual(
            Localizable.downloadingHeld.localized(with: 33, Localizable.hotspotHoldWaiting.localized),
            "Baixando, 33%. Aguardando Wi-Fi: em um Acesso Pessoal"
        )
    }
}

/// Count strings that pick a plural variant from their number (#180: a one-chapter LibriVox book
/// read "1 chapters").
final class LocalizationPluralTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        AbbayBundle.languageCode = nil
    }

    override func tearDownWithError() throws {
        AbbayBundle.value.unsetLocalizedLanguage()
        AbbayBundle.languageCode = nil
        try super.tearDownWithError()
    }

    /// A one-chapter LibriVox book read "1 chapters" (#180): the count picks a plural variant.
    func test_chaptersCount_isSingularForOneAndPluralOtherwise_inEnglish() {
        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "en"))

        XCTAssertEqual(Localizable.chaptersCount.localized(with: 1), "1 chapter")
        XCTAssertEqual(Localizable.chaptersCount.localized(with: 2), "2 chapters")
        XCTAssertEqual(Localizable.chaptersCount.localized(with: 0), "0 chapters")
    }

    /// Portuguese counts 0 as singular, so 0 has its own variant: "0 capítulos", not "0 capítulo".
    func test_chaptersCount_isSingularForOneAndPluralOtherwise_inPortuguese() {
        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        XCTAssertEqual(Localizable.chaptersCount.localized(with: 1), "1 capítulo")
        XCTAssertEqual(Localizable.chaptersCount.localized(with: 2), "2 capítulos")
        XCTAssertEqual(Localizable.chaptersCount.localized(with: 0), "0 capítulos")
    }

    /// The in-app language override (`AbbayBundle.languageCode`) picks the variant too, which is
    /// how the app switches language at run time.
    func test_chaptersCount_followsTheInAppLanguage() {
        AbbayBundle.languageCode = "pt-BR"
        XCTAssertEqual(Localizable.chaptersCount.localized(with: 1), "1 capítulo")
        AbbayBundle.languageCode = "en"
        XCTAssertEqual(Localizable.chaptersCount.localized(with: 1), "1 chapter")
    }
}

private extension Localizable {
    /// Keys with plural variants, whose raw table value is the same `%#@value@` placeholder in
    /// every language: only a formatted count shows their text.
    static let pluralKeys: Set<Localizable> = [.chaptersCount]

    /// What the translation check compares: the string itself, or a plural key formatted.
    var comparableText: String {
        Self.pluralKeys.contains(self) ? localized(with: 2) : localized
    }
}
