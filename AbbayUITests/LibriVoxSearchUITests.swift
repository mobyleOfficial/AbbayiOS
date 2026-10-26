//
//  LibriVoxSearchUITests.swift
//  AbbayUITests
//

import XCTest

/// The redesigned Search tab and book page (#166 G4, G5), on the stub catalog (`-stubLibriVox`):
/// the empty states, the result pill (GET, then OPEN once the book is in the library) and the
/// compact Download/Play pinned in the navigation bar once the big one scrolls away.
final class LibriVoxSearchUITests: XCTestCase {
    private var app = XCUIApplication()

    /// The LibriVox field's placeholder (`Localizable.librivoxSearchPrompt`, English).
    private let libriVoxPrompt = "Search LibriVox"

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Helpers

    private func launch(_ extra: [String] = []) {
        app.launchArguments = [
            LaunchArgument.seedLibrary, LaunchArgument.stubLibriVox, "-AppleLanguages", "(en)"
        ] + extra
        app.launch()
        assertResolves(AccessibilityID.Root.tabSearch)
        element(AccessibilityID.Root.tabSearch).tap()
    }

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

    private func search(_ text: String) {
        let field = app.searchFields
            .matching(NSPredicate(format: "placeholderValue == %@", libriVoxPrompt))
            .firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText(text)
    }

    private func goBack() {
        app.navigationBars.buttons.firstMatch.tap()
    }

    // MARK: - Search states

    func test_withoutMatches_showsNoResults() {
        launch()
        search("zzzzqqq")

        assertResolves(AccessibilityID.Search.noResults)
        XCTAssertFalse(element(AccessibilityID.Search.result(0)).exists)
    }

    func test_offline_showsTheMessage() {
        launch([LaunchArgument.stubPathOffline])
        search("Stub")

        assertResolves(AccessibilityID.Search.message)
        XCTAssertFalse(element(AccessibilityID.Search.result(0)).exists)
    }

    /// GET until the book is in the library, then OPEN. Either way the row opens the page, and
    /// nothing downloads from the list.
    func test_resultPill_saysGet_thenOpenOnceTheBookIsInTheLibrary() {
        launch()
        search("Stub")
        let row = element(AccessibilityID.Search.result(0))
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(row.label.contains("GET"), "row label: \(row.label)")

        row.tap()
        assertResolves(AccessibilityID.Detail.download)
        element(AccessibilityID.Detail.download).tap()
        assertResolves(AccessibilityID.Detail.play)
        goBack()

        XCTAssertTrue(row.waitForExistence(timeout: 15))
        let deadline = Date().addingTimeInterval(5)
        while !row.label.contains("OPEN"), Date() < deadline {
            usleep(200_000)
        }
        XCTAssertTrue(row.label.contains("OPEN"), "row label: \(row.label)")
    }

    // MARK: - Book page

    /// A slow LibriVox (#258, `-stubSlowLibriVox`): the page shows the search result's cover, title
    /// and author with the rest shimmering, then archive.org's chapters and size with the titles
    /// and description shimmering, then LibriVox's. A Download tapped meanwhile waits for them.
    func test_bookPage_onASlowLibriVox_shimmersUntilItsTitlesArrive() {
        launch([LaunchArgument.stubSlowLibriVox])
        assertResolves(AccessibilityID.Search.card(0))
        element(AccessibilityID.Search.card(0)).tap()

        assertResolves(AccessibilityID.Detail.metadataLoading, timeout: 3)
        assertResolves(AccessibilityID.Detail.chaptersLoading, timeout: 1)
        XCTAssertFalse(element(AccessibilityID.Detail.download).isEnabled)

        assertResolves(AccessibilityID.Detail.chapterTitleLoading(0), timeout: 10)
        assertResolves(AccessibilityID.Detail.descriptionLoading, timeout: 1)
        XCTAssertFalse(element(AccessibilityID.Detail.metadataLoading).exists)
        element(AccessibilityID.Detail.download).tap()

        let titlesGone = NSPredicate(format: "exists == false")
        expectation(for: titlesGone, evaluatedWith: element(AccessibilityID.Detail.chapterTitleLoading(0)))
        waitForExpectations(timeout: 15)
        XCTAssertFalse(element(AccessibilityID.Detail.descriptionLoading).exists)
        XCTAssertTrue(app.staticTexts["Stub Chapter"].waitForExistence(timeout: 5))
        // The Download tapped while waiting went through once LibriVox answered.
        assertResolves(AccessibilityID.Detail.play)
    }

    /// The stub catalog's last Popular book (*Emma*) has 24 chapters, so its page scrolls the big
    /// button away: the compact one appears in the navigation bar and does the same thing.
    func test_bookPage_pinsTheActionOnceItScrollsAway() {
        launch()
        assertResolves(AccessibilityID.Search.card(5))
        element(AccessibilityID.Search.card(5)).tap()
        assertResolves(AccessibilityID.Detail.download)
        XCTAssertFalse(element(AccessibilityID.Detail.pinnedDownload).exists)

        app.swipeUp()
        app.swipeUp()

        assertResolves(AccessibilityID.Detail.pinnedDownload)
        element(AccessibilityID.Detail.pinnedDownload).tap()
        assertResolves(AccessibilityID.Detail.pinnedPlay)
        XCTAssertFalse(element(AccessibilityID.Detail.pinnedDownload).exists)
    }
}
