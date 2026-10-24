//
//  MiniPlayerUITests.swift
//  AbbayUITests
//

import XCTest

/// The one-row mini player: its identifiers, tap to open, hiding under the open details screen,
/// and the inset that keeps it off the last row. Seeded books have no audio, but pressing play
/// still loads one, which is all the bar needs.
final class MiniPlayerUITests: XCTestCase {
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

    /// The player slides up from the bottom; wait until its header is near the top.
    private func waitForPlayerToArrive(file: StaticString = #filePath, line: UInt = #line) {
        let close = element(AccessibilityID.Player.close)
        XCTAssertTrue(close.waitForExistence(timeout: 15), "the player has no close button", file: file, line: line)
        let deadline = Date().addingTimeInterval(5)
        while close.frame.minY > app.frame.height / 4, Date() < deadline {
            usleep(100_000)
        }
    }

    // MARK: - Tests

    /// Loads a seeded book by pressing its row's play button. There is no audio behind it, but
    /// the player announces the book, which is all the bar needs.
    private func loadSeededBook(
        titled title: String,
        arguments: [String] = [LaunchArgument.seedLibrary]
    ) throws {
        launch(arguments)
        assertResolves(AccessibilityID.Library.list)
        let index = try XCTUnwrap(rowIndex(titled: title), "no seeded row titled \"\(title)\"")
        element(AccessibilityID.Element.play(AccessibilityID.Library.row(index))).tap()
        assertResolves(AccessibilityID.MiniPlayer.bar)
    }

    func test_miniPlayer_identifiersResolve() throws {
        try loadSeededBook(titled: "Seeded Chaptered Book")

        assertResolves(AccessibilityID.MiniPlayer.bar)
        assertResolves(AccessibilityID.MiniPlayer.playPause)
        assertResolves(AccessibilityID.MiniPlayer.progress)
        let bar = element(AccessibilityID.MiniPlayer.bar)
        XCTAssertTrue(bar.label.contains("Seeded Chaptered Book"), "title missing from \"\(bar.label)\"")
        XCTAssertTrue(bar.label.contains("Chapter 1"), "subtitle missing from \"\(bar.label)\"")
    }

    func test_tappingMiniPlayer_opensDetails() throws {
        try loadSeededBook(titled: "Seeded Chaptered Book")
        let bar = element(AccessibilityID.MiniPlayer.bar)

        bar.tap()

        assertResolves(AccessibilityID.Player.title)
        XCTAssertEqual(element(AccessibilityID.Player.title).label, "Seeded Chaptered Book")
        waitForPlayerToArrive()
        // Hidden while the details screen is fully open, back once it closes.
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "the bar is still there under the open player")
        element(AccessibilityID.Player.close).tap()
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "the bar did not come back after closing")
    }

    /// The bar and the tab bar inset the list: scrolled to the bottom, the last row ends above
    /// the bar (the spec's anti-goal: the mini player never covers list content).
    func test_lastRow_isNotCoveredByMiniPlayer() throws {
        try loadSeededBook(
            titled: "Seeded Chaptered Book",
            arguments: [LaunchArgument.seedLibrary, LaunchArgument.seedFillerBooks]
        )
        let list = element(AccessibilityID.Library.list)
        // Two seeded books and twelve fillers.
        let lastRow = AccessibilityID.Library.row(13)
        let title = element(AccessibilityID.Element.title(lastRow))
        let detail = element(AccessibilityID.Element.detail(lastRow))

        for _ in 0..<6 {
            list.swipeUp()
        }
        // Let the deceleration and any bounce settle.
        sleep(2)

        XCTAssertTrue(title.waitForExistence(timeout: 5), "the last row never appeared")
        let bar = element(AccessibilityID.MiniPlayer.bar)
        let playPause = element(AccessibilityID.MiniPlayer.playPause)
        XCTAssertTrue(bar.exists)
        let barTop = min(bar.frame.minY, playPause.frame.minY)
        XCTAssertLessThanOrEqual(title.frame.maxY, barTop, "last title \(title.frame) vs bar top \(barTop)")
        XCTAssertLessThanOrEqual(detail.frame.maxY, barTop, "last detail \(detail.frame) vs bar top \(barTop)")
    }
}
