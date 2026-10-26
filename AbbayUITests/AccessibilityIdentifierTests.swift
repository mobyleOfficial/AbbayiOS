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
        waitForPlayerToArrive()
        return index
    }

    /// The player slides up from the bottom; tapping inside it mid-slide can miss.
    private func waitForPlayerToArrive(file: StaticString = #filePath, line: UInt = #line) {
        let close = element(AccessibilityID.Player.close)
        XCTAssertTrue(close.waitForExistence(timeout: 15), "the player has no close button", file: file, line: line)
        let deadline = Date().addingTimeInterval(5)
        while close.frame.minY > app.frame.height / 4, Date() < deadline {
            usleep(100_000)
        }
        let arrived = close.frame.minY <= app.frame.height / 4
        XCTAssertTrue(arrived, "the player never arrived (close at \(close.frame.minY))", file: file, line: line)
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

    /// The Search tab replaced "Browse LibriVox": the ＋ menu only imports a file.
    func test_addMenu_offersImportOnly() {
        launch([LaunchArgument.resetLibrary])
        assertResolves(AccessibilityID.Library.toolbarAdd)

        element(AccessibilityID.Library.toolbarAdd).tap()

        assertResolves(AccessibilityID.Library.menuImport)
        XCTAssertFalse(element("library.menu.browse").exists)
    }

    func testEmptyLibrary_showsBothAddButtons() {
        launch([LaunchArgument.resetLibrary])

        assertResolves(AccessibilityID.Library.emptyBrowse)
        assertResolves(AccessibilityID.Library.emptyImport)
    }

    func test_emptyLibrary_hasNoSearchField() {
        launch([LaunchArgument.resetLibrary])
        assertResolves(AccessibilityID.Library.empty)

        XCTAssertFalse(searchField(prompt: libraryPrompt).exists)
    }

    // MARK: - Tabs

    /// The LibriVox field's placeholder (`Localizable.librivoxSearchPrompt`, English).
    private let libriVoxPrompt = "Search LibriVox"
    /// The Library field's placeholder (`Localizable.librarySearchPrompt`, English).
    private let libraryPrompt = "Search your library"

    private func openSearchTab() {
        assertResolves(AccessibilityID.Root.tabSearch)
        element(AccessibilityID.Root.tabSearch).tap()
    }

    /// The visible search field whose placeholder is `prompt`.
    private func searchField(prompt: String) -> XCUIElement {
        app.searchFields.matching(NSPredicate(format: "placeholderValue == %@", prompt)).firstMatch
    }

    func test_tabs_switchBetweenLibraryAndSearch() {
        launch([LaunchArgument.seedLibrary, LaunchArgument.stubLibriVox])
        assertResolves(AccessibilityID.Library.list)
        assertResolves(AccessibilityID.Root.tabLibrary)
        assertResolves(AccessibilityID.Root.tabSearch)

        element(AccessibilityID.Root.tabSearch).tap()
        XCTAssertTrue(searchField(prompt: libriVoxPrompt).waitForExistence(timeout: 15))

        element(AccessibilityID.Root.tabLibrary).tap()
        assertResolves(AccessibilityID.Library.list)
        XCTAssertTrue(searchField(prompt: libraryPrompt).waitForExistence(timeout: 15))
    }

    /// The LibriVox field sits at the top, like the Library's, on every iOS version.
    func test_searchTab_fieldIsAtTheTop() {
        launch([LaunchArgument.seedLibrary, LaunchArgument.stubLibriVox])
        openSearchTab()
        let field = searchField(prompt: libriVoxPrompt)
        XCTAssertTrue(field.waitForExistence(timeout: 15))

        XCTAssertLessThan(field.frame.midY, app.frame.height / 2, "search field at \(field.frame)")
    }

    /// Typing doesn't lift the tab bar above the keyboard: like a system tab bar, it stays
    /// underneath (or is hidden), so the keyboard sits directly under the content.
    func test_typing_doesNotLiftTheTabBarAboveTheKeyboard() throws {
        launch([LaunchArgument.seedLibrary, LaunchArgument.stubLibriVox])
        assertResolves(AccessibilityID.Library.list)
        let tab = element(AccessibilityID.Root.tabLibrary)
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        let field = searchField(prompt: libraryPrompt)
        XCTAssertTrue(field.waitForExistence(timeout: 15))

        field.tap()
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 5) else {
            throw XCTSkip("no software keyboard (hardware keyboard connected)")
        }
        // Let it finish sliding up.
        let deadline = Date().addingTimeInterval(5)
        while keyboard.frame.minY > app.frame.height * 0.75, Date() < deadline {
            usleep(100_000)
        }

        // With the system tab bar's bottom accessory attached (iOS 26.1+), the accessibility tree
        // has reported the keyboard just off screen (minY = screen height) although it is visibly
        // up. Then the top row of keys, which is measured, stands in for it; only when no key is on
        // screen either, the top of a portrait iPhone keyboard (always over 35% of the screen).
        let keyboardTop = keyboard.frame.onScreenTop(height: app.frame.height)
            ?? keyboard.topKeyRow(screenHeight: app.frame.height)
            ?? app.frame.height * 0.65

        if tab.exists {
            // Not exact positions: the system bar on iOS 26 shrinks under the keyboard.
            XCTAssertGreaterThan(
                tab.frame.maxY,
                keyboardTop,
                "the tab bar rides above the keyboard: tab \(tab.frame), keyboard \(keyboard.frame)"
            )
        }
    }

    func test_emptyLibrary_browseButton_opensSearchTab() {
        launch([LaunchArgument.resetLibrary, LaunchArgument.stubLibriVox])
        assertResolves(AccessibilityID.Library.emptyBrowse)

        element(AccessibilityID.Library.emptyBrowse).tap()

        XCTAssertTrue(searchField(prompt: libriVoxPrompt).waitForExistence(timeout: 15))
        assertResolves(AccessibilityID.Search.card(0))
    }

    func test_searchTab_showsPopularCards_andOpensDetails() throws {
        launch([LaunchArgument.seedLibrary, LaunchArgument.stubLibriVox])
        openSearchTab()
        assertResolves(AccessibilityID.Search.card(0))

        element(AccessibilityID.Search.card(0)).tap()

        assertResolves(AccessibilityID.Detail.view)
    }

    // MARK: - Library search

    func test_search_filtersLocalRows() throws {
        launch([LaunchArgument.seedLibrary, LaunchArgument.stubLibriVox])
        assertResolves(AccessibilityID.Library.list)
        let field = searchField(prompt: libraryPrompt)
        XCTAssertTrue(field.waitForExistence(timeout: 15))

        field.tap()
        field.typeText("Chaptered")

        let title = element(AccessibilityID.Element.title(AccessibilityID.Library.row(0)))
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, "Seeded Chaptered Book")
        XCTAssertFalse(element(AccessibilityID.Element.title(AccessibilityID.Library.row(1))).exists)
        XCTAssertFalse(app.staticTexts["Seeded Plain Book"].exists)
    }

    /// The Library search never reaches LibriVox: a query only the stub catalog matches finds nothing.
    func test_librarySearch_isLocalOnly() {
        launch([LaunchArgument.seedLibrary, LaunchArgument.stubLibriVox])
        assertResolves(AccessibilityID.Library.list)
        let field = searchField(prompt: libraryPrompt)
        XCTAssertTrue(field.waitForExistence(timeout: 15))

        field.tap()
        field.typeText("Stub")

        assertResolves(AccessibilityID.Library.noResults)
        XCTAssertFalse(app.staticTexts["Stub LibriVox Book"].exists)
    }

    func test_search_withoutMatches_showsNoResultsState() {
        launch([LaunchArgument.seedLibrary, LaunchArgument.stubLibriVox])
        assertResolves(AccessibilityID.Library.list)
        let field = searchField(prompt: libraryPrompt)
        XCTAssertTrue(field.waitForExistence(timeout: 15))

        field.tap()
        field.typeText("zzzzqqq")

        assertResolves(AccessibilityID.Library.noResults)
        XCTAssertFalse(element(AccessibilityID.Library.empty).exists)
    }

    // MARK: - LibriVox details

    /// Opens the stub client's only remote book from the Search tab. Its details are tiny, so
    /// Download never asks about cellular, and the stub download manager never touches the network.
    private func openStubLibriVoxBook() {
        launch([LaunchArgument.seedLibrary, LaunchArgument.stubLibriVox])
        openSearchTab()
        let field = searchField(prompt: libriVoxPrompt)
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("Stub")
        assertResolves(AccessibilityID.Search.result(0))
        element(AccessibilityID.Search.result(0)).tap()
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

    func test_playFromDetail_opensPlayer_thenLibraryShowsMiniPlayer() {
        openStubLibriVoxBook()
        element(AccessibilityID.Detail.download).tap()
        assertResolves(AccessibilityID.Detail.play)

        element(AccessibilityID.Detail.play).tap()
        // Play opens the same player presentation a Library row opens.
        assertResolves(AccessibilityID.Player.transport(AccessibilityID.Transport.play))
        let playerTitle = element(AccessibilityID.Player.title)
        assertResolves(AccessibilityID.Player.title)
        waitForPlayerToArrive()

        element(AccessibilityID.Player.close).tap()
        XCTAssertTrue(playerTitle.waitForNonExistence(timeout: 15), "the player did not close")
        assertResolves(AccessibilityID.Detail.play)

        // The bar shows on both tabs once a book is loaded.
        assertResolves(AccessibilityID.MiniPlayer.bar)
        element(AccessibilityID.Root.tabLibrary).tap()
        assertResolves(AccessibilityID.MiniPlayer.bar)
        // The added book is in the library behind the details page.
        XCTAssertTrue(app.staticTexts["Stub LibriVox Book"].waitForExistence(timeout: 15))
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
            AccessibilityID.Transport.back,
            AccessibilityID.Transport.play,
            AccessibilityID.Transport.forward
        ] {
            assertResolves(AccessibilityID.Player.transport(control))
        }
        assertResolves(AccessibilityID.Player.speed)
    }

    func test_player_closeButton_dismisses() throws {
        _ = try openPlayer(forBookTitled: "Seeded Chaptered Book")
        let title = element(AccessibilityID.Player.title)

        element(AccessibilityID.Player.close).tap()

        XCTAssertTrue(title.waitForNonExistence(timeout: 15), "the player did not close")
        assertResolves(AccessibilityID.Library.list)
    }

    /// Drags the player down by its header, above the scrolling title and chapter list.
    func test_player_swipeDown_dismisses() throws {
        _ = try openPlayer(forBookTitled: "Seeded Chaptered Book")
        let title = element(AccessibilityID.Player.title)
        let close = element(AccessibilityID.Player.close)

        let start = close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: 500))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(title.waitForNonExistence(timeout: 15), "the player did not close")
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
}

// MARK: - Player chapters

extension AccessibilityIdentifierTests {
    /// The Chapters pill, then the panel it opens (#166 G2): its handle, header and rows.
    func test_player_chapterIdentifiersResolve() throws {
        _ = try openPlayer(forBookTitled: "Seeded Chaptered Book")

        assertResolves(AccessibilityID.Player.chapters)
        element(AccessibilityID.Player.chapters).tap()
        assertResolves(AccessibilityID.Player.chaptersPanel)
        assertResolves(AccessibilityID.Player.chaptersTitle)
        // The seeded chaptered book has three chapters.
        assertResolves(AccessibilityID.Player.chapter(0))
        assertResolves(AccessibilityID.Player.chapter(1))
        revealBelowTheFold(AccessibilityID.Player.chapter(2), swiping: AccessibilityID.Player.chapter(0))
        assertResolves(AccessibilityID.Player.chapter(2))
    }
}

private extension AccessibilityIdentifierTests {
    /// On a shorter screen (the iPhone Duo, the iOS 27.1 runtime's only device) a row can start
    /// below the fold, where the lazy list hasn't built it yet: swipe up on `anchor` to reach it.
    func revealBelowTheFold(_ identifier: String, swiping anchor: String) {
        if !element(identifier).waitForExistence(timeout: 3) {
            element(anchor).swipeUp()
        }
    }
}

private extension CGRect {
    /// `minY`, when the frame has a size and starts on a screen `height` tall.
    func onScreenTop(height: CGFloat) -> CGFloat? {
        self.height > 0 && minY < height ? minY : nil
    }
}

private extension XCUIElement {
    /// The top of a keyboard's first real key (the layout's leading entries are zero-size
    /// padding), when it is on screen.
    func topKeyRow(screenHeight: CGFloat) -> CGFloat? {
        keys.allElementsBoundByIndex.prefix(4)
            .lazy
            .compactMap { $0.frame.onScreenTop(height: screenHeight) }
            .first
    }
}
