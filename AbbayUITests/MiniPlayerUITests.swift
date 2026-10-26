//
//  MiniPlayerUITests.swift
//  AbbayUITests
//

import XCTest

/// The one-row mini player: its identifiers, tap to open, hiding under the open details screen,
/// and the inset that keeps it off the last row. Seeded books play the Debug-only fixture's audio
/// (#147); the bar only needs the book loaded.
final class MiniPlayerUITests: XCTestCase {
    var app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Helpers

    func launch(_ arguments: [String]) {
        app.launchArguments = arguments
        app.launch()
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func assertResolves(
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
    func rowIndex(titled title: String, maxRows: Int = 4) -> Int? {
        for index in 0..<maxRows {
            let candidate = element(AccessibilityID.Element.title(AccessibilityID.Library.row(index)))
            if candidate.exists, candidate.label == title {
                return index
            }
        }
        return nil
    }

    /// The player slides up from the bottom; wait until its header is near the top.
    func waitForPlayerToArrive(file: StaticString = #filePath, line: UInt = #line) {
        let close = element(AccessibilityID.Player.close)
        XCTAssertTrue(close.waitForExistence(timeout: 15), "the player has no close button", file: file, line: line)
        let deadline = Date().addingTimeInterval(5)
        while close.frame.minY > app.frame.height / 4, Date() < deadline {
            usleep(100_000)
        }
    }

    // MARK: - Tests

    /// Loads a seeded book with its cell's context-menu Play: it plays, and the bar shows it.
    func loadSeededBook(
        titled title: String,
        arguments: [String] = [LaunchArgument.seedLibrary]
    ) throws {
        launch(arguments)
        assertResolves(AccessibilityID.Library.list)
        let index = try XCTUnwrap(rowIndex(titled: title), "no seeded row titled \"\(title)\"")
        LibraryGridActions.togglePlayback(in: app, cell: index)
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

    /// #166's owner decision: a chapter tap plays that chapter of the shown book, even with nothing
    /// playing. The book isn't loaded, so the tap loads it, and the bar shows it once the screen
    /// closes, at that chapter. (Before, the tap did nothing while paused.) Chapter 4 starts at 3:00,
    /// inside the seed's audio (#147).
    func test_tappingAChapter_ofABookNotLoaded_loadsIt() throws {
        launch([LaunchArgument.seedLibrary, LaunchArgument.seedLongBook])
        assertResolves(AccessibilityID.Library.list)
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Long Book"), "no seeded long book")
        element(AccessibilityID.Element.title(AccessibilityID.Library.row(index))).tap()
        waitForPlayerToArrive()
        XCTAssertFalse(element(AccessibilityID.MiniPlayer.bar).exists, "nothing should be loaded yet")

        openChaptersPanel()
        let chapter = element(AccessibilityID.Player.chapter(3))
        // On a short screen the panel can show only a few rows, with the fourth clipped under its
        // bottom edge. Scroll the list up by two rows, slowly and holding at the end so it
        // doesn't coast: the row lands well inside the panel on any screen. (A swipe would fling
        // 60 rows past it.)
        let first = element(AccessibilityID.Player.chapter(0))
        let third = element(AccessibilityID.Player.chapter(2))
        XCTAssertTrue(first.waitForExistence(timeout: 5) && third.waitForExistence(timeout: 5))
        third.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 0.1,
            thenDragTo: first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
            withVelocity: 200,
            thenHoldForDuration: 0.5
        )
        // Let the list settle: a tap on a moving list stops it instead of selecting the row.
        sleep(1)
        XCTAssertTrue(chapter.waitForExistence(timeout: 5))
        chapter.tap()
        // The tap also closes the panel.
        XCTAssertTrue(element(AccessibilityID.Player.chaptersPanel).waitForNonExistence(timeout: 5))
        element(AccessibilityID.Player.close).tap()

        let bar = element(AccessibilityID.MiniPlayer.bar)
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "the chapter tap did not load the book")
        XCTAssertTrue(bar.label.contains("Seeded Long Book"), "the bar shows \"\(bar.label)\"")
        let atChapter = NSPredicate(format: "label CONTAINS %@", "Chapter 4")
        let result = XCTWaiter().wait(for: [expectation(for: atChapter, evaluatedWith: bar)], timeout: 10)
        XCTAssertEqual(result, .completed, "the bar is not at the tapped chapter: \"\(bar.label)\"")
    }

    /// The bar and the tab bar inset the grid: scrolled to the bottom, the last cell ends above
    /// the bar (the spec's anti-goal: the mini player never covers library content).
    func test_lastCell_isNotCoveredByMiniPlayer() throws {
        try loadSeededBook(
            titled: "Seeded Chaptered Book",
            arguments: [LaunchArgument.seedLibrary, LaunchArgument.seedFillerBooks]
        )
        let list = element(AccessibilityID.Library.list)
        // Two seeded books and twelve fillers: the last grid row holds cells 12 and 13.
        let lastRow = AccessibilityID.Library.row(13)
        let title = element(AccessibilityID.Element.title(lastRow))
        let detail = element(AccessibilityID.Element.detail(lastRow))

        for _ in 0..<6 {
            list.swipeUp()
        }
        // Let the deceleration and any bounce settle.
        sleep(2)

        XCTAssertTrue(title.waitForExistence(timeout: 5), "the last cell never appeared")
        let bar = element(AccessibilityID.MiniPlayer.bar)
        let playPause = element(AccessibilityID.MiniPlayer.playPause)
        XCTAssertTrue(bar.exists)
        let barTop = min(bar.frame.minY, playPause.frame.minY)
        XCTAssertLessThanOrEqual(title.frame.maxY, barTop, "last title \(title.frame) vs bar top \(barTop)")
        XCTAssertLessThanOrEqual(detail.frame.maxY, barTop, "last detail \(detail.frame) vs bar top \(barTop)")
    }

    // MARK: - Interactive expansion

    var transportPlay: XCUIElement {
        element(AccessibilityID.Player.transport(AccessibilityID.Transport.play))
    }

    /// The grabber's center: hidden from accessibility (the chevron is VoiceOver's close), so it
    /// is found from the chevron beside it, at the header's horizontal center.
    func grabberCenter(file: StaticString = #filePath, line: UInt = #line) -> XCUICoordinate {
        let close = element(AccessibilityID.Player.close)
        XCTAssertTrue(close.waitForExistence(timeout: 5), "the details screen has no header", file: file, line: line)
        return app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.midX, dy: close.frame.midY))
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
        let bar = element(AccessibilityID.MiniPlayer.bar)
        let before = restingFrame(of: bar)
        bar.tap()
        waitForPlayerToArrive()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "not settled open")
        let start = grabberCenter()
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))

        start.press(forDuration: 0.1, thenDragTo: end)

        assertCollapsedIntoBar(restingAt: before)
    }

    /// Ruling 14: opened from a row with nothing loaded (grows from the bottom strip), Play loads
    /// the book while open, then a slow collapse lands on the bar that came back meanwhile.
    /// Also the recorded landing scenario.
    func test_collapseAfterPlayingInDetails_landsOnTheBar() throws {
        launch([LaunchArgument.seedLibrary])
        assertResolves(AccessibilityID.Library.list)
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Chaptered Book"))
        element(AccessibilityID.Element.title(AccessibilityID.Library.row(index))).tap()
        waitForPlayerToArrive()
        XCTAssertTrue(transportPlay.waitForExistence(timeout: 5))
        sleep(1)
        transportPlay.tap()
        let start = grabberCenter()
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))

        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: 250, thenHoldForDuration: 0.5)

        assertCollapsedIntoBar()
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
        let before = restingFrame(of: bar)
        let barCenter = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))

        barCenter.press(forDuration: 0.2, thenDragTo: top, withVelocity: 180, thenHoldForDuration: 1)

        XCTAssertTrue(transportPlay.waitForExistence(timeout: 10), "the slow drag did not open the details screen")
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5))
        let grabberCenter = grabberCenter()
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))

        grabberCenter.press(forDuration: 0.2, thenDragTo: bottom, withVelocity: 180, thenHoldForDuration: 1)

        assertCollapsedIntoBar(restingAt: before)
    }
}

// MARK: - Collapse checks

extension MiniPlayerUITests {
    /// The bar's frame once it has stopped moving (two reads 0.2 s apart agree), or its last frame
    /// after `timeout`.
    func restingFrame(of bar: XCUIElement, timeout: TimeInterval = 5) -> CGRect {
        var previous = bar.frame
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            usleep(200_000)
            let current = bar.frame
            if current == previous { return current }
            previous = current
        }
        return previous
    }

    /// A collapse has landed: the details screen is gone, and the bar is back, at rest along the
    /// bottom, taking touches, and (when known) where it was before the open. Not just "a bar
    /// exists": it reappears as soon as a collapse starts, even one that settles open again.
    func assertCollapsedIntoBar(
        restingAt expected: CGRect? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let bar = element(AccessibilityID.MiniPlayer.bar)
        XCTAssertTrue(
            transportPlay.waitForNonExistence(timeout: 10),
            "the details screen is still open",
            file: file,
            line: line
        )
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "the bar did not come back", file: file, line: line)
        let frame = restingFrame(of: bar)
        XCTAssertGreaterThan(
            frame.minY,
            app.frame.height * 0.75,
            "the bar is not along the bottom: \(frame)",
            file: file,
            line: line
        )
        XCTAssertTrue(bar.isHittable, "the bar does not take touches after the collapse", file: file, line: line)
        XCTAssertTrue(
            element(AccessibilityID.MiniPlayer.playPause).isHittable,
            "the bar's play button is covered after the collapse",
            file: file,
            line: line
        )
        if let expected {
            XCTAssertEqual(frame.minY, expected.minY, accuracy: 2, "bar \(frame) vs \(expected) before the open", file: file, line: line)
            XCTAssertEqual(frame.height, expected.height, accuracy: 2, "bar \(frame) vs \(expected) before the open", file: file, line: line)
        }
    }
}
