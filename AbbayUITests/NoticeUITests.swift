//
//  NoticeUITests.swift
//  AbbayUITests
//

import XCTest

/// The error banner (#115): a failed import and a book whose file is gone both say so, and the
/// banner goes away by itself. `-stubFailingImport` imports two files that don't exist instead of
/// presenting the system picker; the seeded books' files don't exist either.
final class NoticeUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Helpers

    private func launch(_ arguments: [String]) {
        app.launchArguments = arguments
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var banner: XCUIElement {
        element(AccessibilityID.Notice.banner)
    }

    /// Row order isn't insertion order (`LoadAllAudiosUseCase` doesn't sort): find it by title.
    private func rowIndex(titled title: String, maxRows: Int = 4) -> Int? {
        for index in 0..<maxRows {
            let candidate = element(AccessibilityID.Element.title(AccessibilityID.Library.row(index)))
            if candidate.exists, candidate.label == title {
                return index
            }
        }
        return nil
    }

    // MARK: - Tests

    func test_failedImport_showsABannerNamingTheFiles_thatGoesAwayByItself() {
        launch([LaunchArgument.resetLibrary, LaunchArgument.stubFailingImport])
        let importButton = element(AccessibilityID.Library.emptyImport)
        XCTAssertTrue(importButton.waitForExistence(timeout: 15))

        importButton.tap()

        XCTAssertTrue(banner.waitForExistence(timeout: 10), "no banner after a failed import")
        XCTAssertTrue(banner.label.contains("Couldn't import 2 files"), "unexpected: \"\(banner.label)\"")
        XCTAssertTrue(banner.label.contains("Missing Book.mp3"), "file name missing: \"\(banner.label)\"")
        XCTAssertTrue(banner.label.contains("Broken Book.m4b"), "file name missing: \"\(banner.label)\"")
        // Nothing was added, so the empty state stays.
        XCTAssertTrue(element(AccessibilityID.Library.empty).exists)
        XCTAssertTrue(banner.waitForNonExistence(timeout: 15), "the banner did not dismiss itself")
    }

    /// `-seedMissingFile`'s book has no file, which is what a moved or renamed import looks like.
    /// The bar still appears (the book is loaded), and the banner says how to recover.
    func test_playingABookWhoseFileIsGone_saysItMovedAndToImportItAgain() throws {
        launch([LaunchArgument.seedLibrary, LaunchArgument.seedMissingFile])
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 15))
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Missing Book"))

        LibraryGridActions.togglePlayback(in: app, cell: index)

        XCTAssertTrue(banner.waitForExistence(timeout: 10), "no banner for a missing file")
        XCTAssertTrue(banner.label.contains("Seeded Missing Book"), "title missing: \"\(banner.label)\"")
        XCTAssertTrue(banner.label.contains("Import it again"), "no recovery hint: \"\(banner.label)\"")
        XCTAssertTrue(element(AccessibilityID.MiniPlayer.bar).exists, "the bar must still appear")
    }

    /// After the failure the cell's menu and the bar show Play, not Pause, so one tap retries: the
    /// banner comes back after it had gone, and the button still shows Play.
    func test_afterABookFailsToPlay_theButtonsShowPlay_andOneTapRetries() throws {
        launch([LaunchArgument.seedLibrary, LaunchArgument.seedMissingFile])
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 15))
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Missing Book"))
        let barPlay = element(AccessibilityID.MiniPlayer.playPause)

        LibraryGridActions.togglePlayback(in: app, cell: index)
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "no banner for a missing file")
        XCTAssertTrue(barPlay.waitForExistence(timeout: 10))
        assertLabel(of: barPlay, becomes: "Play")
        XCTAssertEqual(LibraryGridActions.playbackItemLabel(in: app, cell: index), "Play")
        XCTAssertTrue(banner.waitForNonExistence(timeout: 15), "the banner did not dismiss itself")

        barPlay.tap()

        XCTAssertTrue(banner.waitForExistence(timeout: 10), "one tap on Play did not retry")
        assertLabel(of: barPlay, becomes: "Play")
    }

    /// #196: what the moved-file banner asks for. `-stubMovedImport` imports *Seeded Missing Book*'s
    /// file from where it moved to; the book is relinked to it, not added again, and then plays.
    func test_importingAMovedBooksFileAgain_relinksTheBook_insteadOfAddingASecond() throws {
        launch([LaunchArgument.seedLibrary, LaunchArgument.seedMissingFile, LaunchArgument.stubMovedImport])
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 15))
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Missing Book"))
        let extraRow = element(AccessibilityID.Element.title(AccessibilityID.Library.row(3)))
        XCTAssertFalse(extraRow.exists, "the seed is three books")

        element(AccessibilityID.Library.toolbarAdd).tap()
        element(AccessibilityID.Library.menuImport).tap()

        XCTAssertFalse(extraRow.waitForExistence(timeout: 5), "the import added a second book")
        XCTAssertEqual(rowIndex(titled: "Seeded Missing Book"), index)
        LibraryGridActions.togglePlayback(in: app, cell: index)
        assertLabel(of: element(AccessibilityID.MiniPlayer.playPause), becomes: "Pause")
        XCTAssertFalse(banner.exists, "the relinked book still reads as moved")
    }

    private func assertLabel(of element: XCUIElement, becomes label: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@", label)
        let result = XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 10)
        XCTAssertEqual(result, .completed, "label is \"\(element.label)\", expected \"\(label)\"", file: file, line: line)
    }

    /// The banner sits over the navigation bar but doesn't take touches.
    func test_whileTheBannerShows_theToolbarUnderItStillWorks() {
        launch([LaunchArgument.resetLibrary, LaunchArgument.stubFailingImport])
        let importButton = element(AccessibilityID.Library.emptyImport)
        XCTAssertTrue(importButton.waitForExistence(timeout: 15))
        importButton.tap()
        XCTAssertTrue(banner.waitForExistence(timeout: 10))

        element(AccessibilityID.Library.toolbarAdd).tap()

        XCTAssertTrue(
            element(AccessibilityID.Library.menuImport).waitForExistence(timeout: 5),
            "the add menu did not open under the banner"
        )
    }
}
