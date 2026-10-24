//
//  AccessibilityIdentifierTests.swift
//  AbbayUITests
//

import XCTest

/// Proves that every accessibility identifier the feature map promises actually resolves in the
/// running app.
///
/// Identifiers are declarative, so nothing else in the repo can verify them. SwiftUI applies
/// `.accessibilityIdentifier` to **every** accessibility element in a subtree, which means an
/// identifier on a container silently overwrites its children's -- the first version of this
/// suite caught exactly that, with a row container clobbering its title, play button, chapter
/// count and timestamp. Hence the rule the app now follows: identifiers on leaves only.
///
/// State comes from `-seedLibrary` / `-resetLibrary` (see `LaunchArgument`), handled by
/// `UITestSeeder` in DEBUG builds.
final class AccessibilityIdentifierTests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // No `tearDown` terminating the app on purpose. `app.launch()` already terminates and
    // relaunches a running instance, and an explicit `terminate()` between tests left the
    // simulator unable to hand out a background assertion on CI -- five of nine tests failed
    // with "Timed out while acquiring background assertion" at the *next* test's launch.

    // MARK: - Helpers

    private func launch(_ arguments: [String]) {
        app.launchArguments = arguments
        app.launch()
    }

    /// Type-agnostic lookup. A driver needs the identifier to resolve; which `XCUIElementType`
    /// SwiftUI happened to emit is an implementation detail not worth hard-coding.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertResolves(
        _ identifier: String,
        timeout: TimeInterval = 15,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element(identifier).waitForExistence(timeout: timeout),
            "no element resolves identifier \"\(identifier)\"",
            file: file,
            line: line
        )
    }

    /// Row order comes straight from `LoadAllAudiosUseCase`, which applies no sort, so the
    /// seeded books do not appear in insertion order. Resolve a row by its title instead of
    /// assuming an index.
    private func rowIndex(titled title: String, maxRows: Int = 4) -> Int? {
        for index in 0..<maxRows {
            let candidate = element(AccessibilityID.Element.title(AccessibilityID.Library.row(index)))
            if candidate.exists, candidate.label == title {
                return index
            }
        }
        return nil
    }

    private func openPlayer(forBookTitled title: String) throws -> Int {
        launch([LaunchArgument.seedLibrary])
        assertResolves(AccessibilityID.Library.list)
        let index = try XCTUnwrap(rowIndex(titled: title), "no seeded row titled \"\(title)\"")
        element(AccessibilityID.Element.title(AccessibilityID.Library.row(index))).tap()
        assertResolves(AccessibilityID.Player.transport(AccessibilityID.Transport.play))
        return index
    }

    // MARK: - Library

    func test_emptyLibrary_emptyStateResolves() {
        launch([LaunchArgument.resetLibrary])

        assertResolves(AccessibilityID.Library.empty)
    }

    func test_toolbarIdentifiersResolve() {
        launch([LaunchArgument.resetLibrary])

        assertResolves(AccessibilityID.Library.toolbarAdd)
        assertResolves(AccessibilityID.Library.toolbarSettings)
    }

    func test_addMenu_offersBrowseAndImport() {
        launch([LaunchArgument.resetLibrary])
        assertResolves(AccessibilityID.Library.toolbarAdd)

        element(AccessibilityID.Library.toolbarAdd).tap()

        assertResolves(AccessibilityID.Library.menuBrowse)
        assertResolves(AccessibilityID.Library.menuImport)
    }

    func testEmptyLibrary_showsBothAddButtons() {
        launch([LaunchArgument.resetLibrary])

        assertResolves(AccessibilityID.Library.emptyBrowse)
        assertResolves(AccessibilityID.Library.emptyImport)
    }

    func test_emptyLibrary_hasNoSearchField() {
        launch([LaunchArgument.resetLibrary])
        assertResolves(AccessibilityID.Library.empty)

        XCTAssertFalse(app.searchFields.firstMatch.exists)
    }

    // MARK: - Search

    func test_search_filtersLocalRows() throws {
        launch([LaunchArgument.seedLibrary, LaunchArgument.stubLibriVox])
        assertResolves(AccessibilityID.Library.list)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))

        field.tap()
        field.typeText("Chaptered")

        let title = element(AccessibilityID.Element.title(AccessibilityID.Library.localRow(0)))
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, "Seeded Chaptered Book")
        XCTAssertFalse(element(AccessibilityID.Element.title(AccessibilityID.Library.localRow(1))).exists)
        XCTAssertFalse(app.staticTexts["Seeded Plain Book"].exists)
    }

    /// Drags a sheet down by its grabber area. Swiping a content element doesn't work: the player's
    /// scrolling title and chapter list take the gesture.
    private func dismissSheet() {
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        top.press(forDuration: 0.1, thenDragTo: bottom)
    }

    /// Opens the stub client's only remote book. Its details are tiny, so Download never asks
    /// about cellular, and the stub download manager never touches the network.
    private func openStubLibriVoxBook() {
        launch([LaunchArgument.seedLibrary, LaunchArgument.stubLibriVox])
        assertResolves(AccessibilityID.Library.list)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("Stub")
        assertResolves(AccessibilityID.Library.remoteRow(0))
        element(AccessibilityID.Library.remoteRow(0)).tap()
        assertResolves(AccessibilityID.Detail.download)
    }

    /// Regression: adding the book removed its search row, and the row-owned navigation link
    /// popped the page before Play could appear.
    func test_libriVoxDownload_keepsDetailPageOpenAndShowsPlay() {
        openStubLibriVoxBook()

        element(AccessibilityID.Detail.download).tap()

        assertResolves(AccessibilityID.Detail.play)
        XCTAssertTrue(element(AccessibilityID.Detail.view).exists)
        XCTAssertFalse(element(AccessibilityID.Detail.download).exists)
    }

    func test_search_showsFloatingPlayerAfterPlayingFromDetail() {
        openStubLibriVoxBook()
        element(AccessibilityID.Detail.download).tap()
        assertResolves(AccessibilityID.Detail.play)

        element(AccessibilityID.Detail.play).tap()
        // Play opens the same full player sheet a Library row opens.
        assertResolves(AccessibilityID.Player.transport(AccessibilityID.Transport.play))
        let playerTitle = element(AccessibilityID.Player.title)
        assertResolves(AccessibilityID.Player.title)

        dismissSheet()
        XCTAssertTrue(playerTitle.waitForNonExistence(timeout: 15), "the player sheet did not dismiss")
        assertResolves(AccessibilityID.Detail.play)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        assertResolves(AccessibilityID.Library.floatingPlayer)
        // Still in search: the added book is now an "In your library" result.
        XCTAssertTrue(element(AccessibilityID.Element.title(AccessibilityID.Library.localRow(0))).exists)
    }

    func test_search_withoutMatches_showsNoResultsState() {
        launch([LaunchArgument.seedLibrary, LaunchArgument.stubLibriVox])
        assertResolves(AccessibilityID.Library.list)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))

        field.tap()
        field.typeText("zzzzqqq")

        assertResolves(AccessibilityID.Library.noResults)
        XCTAssertFalse(element(AccessibilityID.Library.empty).exists)
    }

    func test_seededLibrary_listResolves() {
        launch([LaunchArgument.seedLibrary])

        assertResolves(AccessibilityID.Library.list)
    }

    func test_seededLibrary_rowLeafIdentifiersResolve() throws {
        launch([LaunchArgument.seedLibrary])
        assertResolves(AccessibilityID.Library.list)
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Chaptered Book"))
        let row = AccessibilityID.Library.row(index)

        assertResolves(AccessibilityID.Element.artwork(row))
        assertResolves(AccessibilityID.Element.title(row))
        assertResolves(AccessibilityID.Element.detail(row))
        assertResolves(AccessibilityID.Element.play(row))
    }

    /// Each row must carry its own identifiers rather than inheriting a container's, or a driver
    /// cannot tell the row apart from the play button inside it.
    func test_rowIdentifiersAreDistinctPerRow() throws {
        launch([LaunchArgument.seedLibrary])
        assertResolves(AccessibilityID.Library.list)

        let chaptered = try XCTUnwrap(rowIndex(titled: "Seeded Chaptered Book"))
        let plain = try XCTUnwrap(rowIndex(titled: "Seeded Plain Book"))

        XCTAssertNotEqual(chaptered, plain, "the two seeded books must occupy different rows")
    }

    // MARK: - Player

    func test_tappingRow_opensPlayer() throws {
        _ = try openPlayer(forBookTitled: "Seeded Chaptered Book")
    }

    func test_player_transportIdentifiersResolve() throws {
        _ = try openPlayer(forBookTitled: "Seeded Chaptered Book")

        for control in [
            AccessibilityID.Transport.back30,
            AccessibilityID.Transport.back15,
            AccessibilityID.Transport.play,
            AccessibilityID.Transport.forward15,
            AccessibilityID.Transport.forward30
        ] {
            assertResolves(AccessibilityID.Player.transport(control))
        }
    }

    func test_player_titleResolves() throws {
        _ = try openPlayer(forBookTitled: "Seeded Chaptered Book")

        assertResolves(AccessibilityID.Player.title)
    }

    // MARK: - Displayed values

    /// End-to-end guard for #104. The counter is rendered from a 0-based index by
    /// `ChapterCountView`, so a three-chapter book at rest must read 1/3 -- it previously read
    /// 0/3 until playback reported a time. Substring rather than equality because the detail line
    /// also carries the author.
    func test_seededChapteredRow_showsOneBasedChapterCounter() throws {
        launch([LaunchArgument.seedLibrary])
        assertResolves(AccessibilityID.Library.list)
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Chaptered Book"))
        let counter = element(AccessibilityID.Element.detail(AccessibilityID.Library.row(index)))
        XCTAssertTrue(counter.waitForExistence(timeout: 15))

        XCTAssertTrue(
            counter.label.contains("Ch 1/3"),
            "expected a 1-based counter for a three-chapter book, got \"\(counter.label)\""
        )
    }

    /// A book without chapters shows the time left instead of a chapter counter.
    func test_seededPlainRow_showsAuthorAndTimeLeft() throws {
        launch([LaunchArgument.seedLibrary])
        assertResolves(AccessibilityID.Library.list)
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Plain Book"))
        let detail = element(AccessibilityID.Element.detail(AccessibilityID.Library.row(index)))
        XCTAssertTrue(detail.waitForExistence(timeout: 15))

        XCTAssertTrue(detail.label.contains("Seed Author"), "author missing from \"\(detail.label)\"")
        XCTAssertTrue(detail.label.contains("left"), "expected the time left, got \"\(detail.label)\"")
        XCTAssertFalse(detail.label.contains("Ch "), "a book without chapters has no counter: \"\(detail.label)\"")
    }

    func test_player_chapterIdentifiersResolve() throws {
        _ = try openPlayer(forBookTitled: "Seeded Chaptered Book")

        assertResolves(AccessibilityID.Player.chaptersTitle)
        // The seeded chaptered book has three chapters.
        assertResolves(AccessibilityID.Player.chapter(0))
        assertResolves(AccessibilityID.Player.chapter(1))
        assertResolves(AccessibilityID.Player.chapter(2))
    }
}
