//
//  LibriVoxScreensTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The pure decisions of the redesigned Search tab and LibriVox book page (#166 G4, G5).
final class LibriVoxScreensTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        AbbayBundle.languageCode = nil
    }

    override func tearDownWithError() throws {
        AbbayBundle.value.unsetLocalizedLanguage()
        AbbayBundle.languageCode = nil
        try super.tearDownWithError()
    }

    private func book(id: String = "b1", seconds: Double = 11_100, chapters: Int = 12) -> LibriVoxBook {
        LibriVoxBook(
            id: id,
            title: "Title",
            authors: "Author",
            descriptionText: "",
            language: "eng",
            totalSeconds: seconds,
            coverURL: URL(fileURLWithPath: "/dev/null"),
            sections: (0..<chapters).map {
                LibriVoxBook.Section(title: "C\($0)", seconds: 60, listenURL: URL(fileURLWithPath: "/dev/null"))
            }
        )
    }

    // MARK: - Search result pill

    func test_resultPill_saysGet_unlessTheBookIsInTheLibrary() {
        XCTAssertEqual(LibriVoxBookRow.action(for: book(id: "a"), libraryBookIDs: []), .get)
        XCTAssertEqual(LibriVoxBookRow.action(for: book(id: "a"), libraryBookIDs: ["b"]), .get)
        XCTAssertEqual(LibriVoxBookRow.action(for: book(id: "a"), libraryBookIDs: ["a", "b"]), .open)
    }

    func test_resultPill_isTranslated() {
        AbbayBundle.languageCode = "en"
        XCTAssertEqual(LibriVoxBookRow.Action.get.title, "GET")
        XCTAssertEqual(LibriVoxBookRow.Action.open.title, "OPEN")

        AbbayBundle.languageCode = "pt-BR"
        XCTAssertEqual(LibriVoxBookRow.Action.get.title, "OBTER")
        XCTAssertEqual(LibriVoxBookRow.Action.open.title, "ABRIR")
    }

    // MARK: - Book page metadata line

    /// Duration · chapters · size, all in the app's language: "296.7 MB" in English whatever the
    /// device's locale, "296,7 MB" in pt-BR.
    func test_metadataLine_followsTheAppLanguage() {
        AbbayBundle.languageCode = "en"
        XCTAssertEqual(
            LibriVoxDetailView.metadataText(book: book(), totalBytes: 296_700_000),
            "3h 5m · 12 chapters · 296.7 MB"
        )

        AbbayBundle.languageCode = "pt-BR"
        XCTAssertEqual(
            LibriVoxDetailView.metadataText(book: book(), totalBytes: 296_700_000),
            "3h 5min · 12 capítulos · 296,7 MB"
        )
    }

    func test_metadataLine_leavesOutAnUnknownSizeAndDuration() {
        AbbayBundle.languageCode = "en"

        XCTAssertEqual(LibriVoxDetailView.metadataText(book: book(chapters: 1), totalBytes: 0), "3h 5m · 1 chapter")
        XCTAssertEqual(LibriVoxDetailView.metadataText(book: book(seconds: 0), totalBytes: 0), "12 chapters")
    }

    // MARK: - Strings

    /// The G4 strings resolve in both languages and are translated (`LocalizationTests` is at its
    /// type-length limit, so they are checked here).
    func test_searchStrings_resolveInBothLanguages() {
        let keys: [Localizable] = [
            .searchIdleTitle, .searchIdleMessage, .searchOfflineTitle, .searchFailedTitle,
            .searchNoResultsHint, .getBook, .openBook
        ]
        AbbayBundle.languageCode = "en"
        let english = keys.map(\.localized)
        AbbayBundle.languageCode = "pt-BR"
        let portuguese = keys.map(\.localized)

        for (index, key) in keys.enumerated() {
            XCTAssertNotEqual(english[index], key.rawValue, "\(key) has no English value")
            XCTAssertNotEqual(portuguese[index], key.rawValue, "\(key) has no pt-BR value")
            XCTAssertNotEqual(english[index], portuguese[index], "\(key) is not translated")
        }
    }

    // MARK: - Pinned action

    func test_pinnedAction_showsOnlyOnceTheBigButtonIsAboveTheScrollView() {
        XCTAssertFalse(LibriVoxDetailView.isScrolledAway(maxY: 300))
        XCTAssertFalse(LibriVoxDetailView.isScrolledAway(maxY: 0))
        XCTAssertTrue(LibriVoxDetailView.isScrolledAway(maxY: -1))
    }
}
