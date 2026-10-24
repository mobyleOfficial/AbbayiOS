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
        .carPlayEmptyLibrarySubtitle
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
        .carPlayEmptyLibrarySubtitle
    ]

    /// Format-only strings (`%d/%d`). They carry no language, so they deliberately ship a single
    /// entry and fall back to the base language rather than being duplicated per locale.
    private let formatOnlyKeys: [Localizable] = [.chapterCount]

    override func tearDownWithError() throws {
        AbbayBundle.value.unsetLocalizedLanguage()
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
        XCTAssertEqual(Localizable.rowTimeLeft.localized(with: "3m"), "3m left")
    }

    func test_miniPlayerSubtitleFormatsItsArguments() {
        XCTAssertEqual(Localizable.miniPlayerSubtitle.localized(with: 35, "12 min"), "Chapter 35 · 12 min left")

        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        XCTAssertEqual(Localizable.miniPlayerSubtitle.localized(with: 35, "12 min"), "Capítulo 35 · 12 min restantes")
    }

    /// pt-BR reads "%@ restantes", not "faltam %@", which is wrong at one minute ("faltam 1 min").
    func test_timeLeftStrings_inPortuguese_readAsRemaining() {
        XCTAssertTrue(AbbayBundle.value.setLocalizedLanguage(to: "pt-BR"))

        XCTAssertEqual(Localizable.rowTimeLeft.localized(with: "1 min"), "1 min restantes")
        XCTAssertEqual(Localizable.miniPlayerSubtitle.localized(with: 2, "1 min"), "Capítulo 2 · 1 min restantes")
        XCTAssertEqual(Localizable.chapterProgress.localized, "Progresso do capítulo")
    }
}
