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

    // MARK: - Interactive expansion

    private var transportPlay: XCUIElement {
        element(AccessibilityID.Player.transport(AccessibilityID.Transport.play))
    }

    /// Drags the bar up to near the top of the screen: the details screen follows and settles open.
    func test_draggingMiniPlayerUp_opensDetails() throws {
        try loadSeededBook(titled: "Seeded Chaptered Book")
        let bar = element(AccessibilityID.MiniPlayer.bar)
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))

        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(transportPlay.waitForExistence(timeout: 10), "the details screen did not open")
        XCTAssertEqual(element(AccessibilityID.Player.title).label, "Seeded Chaptered Book")
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "the bar is still there under the open details screen")
    }

    /// Drags the open details screen down by its grabber: it collapses back into the bar.
    func test_draggingDetailsDown_collapses() throws {
        try loadSeededBook(titled: "Seeded Chaptered Book")
        element(AccessibilityID.MiniPlayer.bar).tap()
        waitForPlayerToArrive()
        let grabber = element(AccessibilityID.Player.grabber)
        XCTAssertTrue(grabber.waitForExistence(timeout: 5), "the details screen has no grabber")
        let start = grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))

        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(element(AccessibilityID.MiniPlayer.bar).waitForExistence(timeout: 10), "the bar did not come back")
        XCTAssertTrue(transportPlay.waitForNonExistence(timeout: 10), "the details screen is still open")
    }

    /// A short, slow drag stays under 30% of the travel: released, it settles back into the bar.
    func test_shortSlowDragUp_settlesClosed() throws {
        try loadSeededBook(titled: "Seeded Chaptered Book")
        let bar = element(AccessibilityID.MiniPlayer.bar)
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: -120))

        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: 150, thenHoldForDuration: 0.5)

        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        // Give the settle time to land and release the screen.
        sleep(1)
        XCTAssertFalse(transportPlay.exists, "a 120 pt drag must not open the details screen")
        XCTAssertTrue(bar.isHittable, "the bar must take touches again once the expansion settled closed")
    }

    /// Slow drags both ways, finger held at the end, as the spec's "a slow drag animates slowly".
    /// Also the scenario recorded for review (`simctl io recordVideo` while it runs).
    func test_slowDrags_openAndCollapse() throws {
        try loadSeededBook(titled: "Seeded Chaptered Book")
        let bar = element(AccessibilityID.MiniPlayer.bar)
        let barCenter = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))

        barCenter.press(forDuration: 0.2, thenDragTo: top, withVelocity: 180, thenHoldForDuration: 1)

        XCTAssertTrue(transportPlay.waitForExistence(timeout: 10), "the slow drag did not open the details screen")
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5))
        let grabber = element(AccessibilityID.Player.grabber)
        let grabberCenter = grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))

        grabberCenter.press(forDuration: 0.2, thenDragTo: bottom, withVelocity: 180, thenHoldForDuration: 1)

        XCTAssertTrue(bar.waitForExistence(timeout: 10), "the slow drag did not collapse the details screen")
        XCTAssertTrue(transportPlay.waitForNonExistence(timeout: 10))
    }
}
