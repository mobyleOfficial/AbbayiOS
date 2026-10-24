//
//  MiniPlayerAccessibilityUITests.swift
//  AbbayUITests
//

import XCTest

/// The mini player for VoiceOver and Reduce Motion: the bar's default and named actions, the
/// details screen's *Close player* chevron and escape scrub, the progress line's label and value,
/// and the expansion with Reduce Motion forced on (`-forceReduceMotion`).
///
/// The actions go through `AccessibilityActions`, which sends what VoiceOver sends: `tap()` is a
/// synthesized touch and would test the gestures instead. The chapter actions need audio that can
/// seek from a known point, so they use `-seedPlayableBook`, whose chapters are the m4b's own (the
/// other seeds play the same audio under made-up chapters, #147).
extension MiniPlayerUITests {
    // MARK: - Helpers

    private var bar: XCUIElement { element(AccessibilityID.MiniPlayer.bar) }
    private var progress: XCUIElement { element(AccessibilityID.MiniPlayer.progress) }

    /// Loads *Seeded Playable Book* (200 s in: chapter 2, 56 s of its 144 s) and pauses it again
    /// straight away, so the position holds still for the assertions (and the Mac stays quiet).
    private func loadPlayableBook(extraArguments: [String] = []) throws {
        try loadSeededBook(
            titled: "Seeded Playable Book",
            arguments: [LaunchArgument.seedLibrary, LaunchArgument.seedPlayableBook] + extraArguments
        )
        let playPause = element(AccessibilityID.MiniPlayer.playPause)
        XCTAssertTrue(playPause.waitForExistence(timeout: 5))
        XCTAssertTrue(wait(for: playPause, label: "Pause"), "not playing: \"\(playPause.label)\"")
        playPause.tap()
        XCTAssertTrue(wait(for: playPause, label: "Play"), "did not pause: \"\(playPause.label)\"")
        XCTAssertTrue(waitForBarLabel(containing: "Chapter 2"), "not in chapter 2: \"\(bar.label)\"")
    }

    private func wait(for element: XCUIElement, label: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.label != label, Date() < deadline {
            usleep(100_000)
        }
        return element.label == label
    }

    /// The progress line's value as a whole percentage ("39%" -> 39).
    private func progressPercent(file: StaticString = #filePath, line: UInt = #line) throws -> Int {
        let value = try XCTUnwrap(progress.value as? String, "the progress line has no value", file: file, line: line)
        let digits = value.filter(\.isNumber)
        return try XCTUnwrap(Int(digits), "not a percentage: \"\(value)\"", file: file, line: line)
    }

    private func waitForBarLabel(containing text: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !bar.label.contains(text), Date() < deadline {
            usleep(100_000)
        }
        return bar.label.contains(text)
    }

    /// Opens the details screen from the bar and waits for it to settle.
    private func openFromBar() {
        bar.tap()
        waitForPlayerToArrive()
        XCTAssertTrue(transportPlay.waitForExistence(timeout: 5), "the details screen did not open")
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "not settled open")
    }

    // MARK: - The bar's actions

    func test_a11y_bar_listsTheNamedActions() throws {
        try loadSeededBook(titled: "Seeded Chaptered Book")

        let names = try AccessibilityActions.customActionNames(of: bar)

        XCTAssertEqual(Set(names), ["Open player", "Next chapter", "Restart chapter"], "\(names)")
        XCTAssertEqual(bar.elementType, .button, "the bar is announced as a button")
    }

    func test_a11y_bar_defaultAction_opensDetails() throws {
        try loadSeededBook(titled: "Seeded Chaptered Book")
        let before = restingFrame(of: bar)

        try AccessibilityActions.activate(bar)

        XCTAssertTrue(transportPlay.waitForExistence(timeout: 10), "activate did not open the details screen")
        XCTAssertEqual(element(AccessibilityID.Player.title).label, "Seeded Chaptered Book")
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "the bar is still there under the open details screen")
        element(AccessibilityID.Player.close).tap()
        assertCollapsedIntoBar(restingAt: before)
    }

    func test_a11y_bar_openPlayerAction_opensDetails() throws {
        try loadSeededBook(titled: "Seeded Chaptered Book")

        try AccessibilityActions.performCustomAction(named: "Open player", on: bar)

        XCTAssertTrue(transportPlay.waitForExistence(timeout: 10), "Open player did not open the details screen")
        XCTAssertEqual(element(AccessibilityID.Player.title).label, "Seeded Chaptered Book")
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "the bar is still there under the open details screen")
    }

    func test_a11y_bar_nextChapterAction_goesToTheNextChapter() throws {
        try loadPlayableBook()
        XCTAssertGreaterThan(try progressPercent(), 30, "the seed is 39% into chapter 2")

        try AccessibilityActions.performCustomAction(named: "Next chapter", on: bar)

        XCTAssertTrue(waitForBarLabel(containing: "Chapter 3"), "Next chapter did not move on: \"\(bar.label)\"")
        XCTAssertLessThanOrEqual(try progressPercent(), 2, "not at the start of chapter 3")
        XCTAssertFalse(transportPlay.exists, "a chapter action must not open the details screen")
    }

    func test_a11y_bar_restartChapterAction_seeksToTheChapterStart() throws {
        try loadPlayableBook()
        XCTAssertGreaterThan(try progressPercent(), 30, "the seed is 39% into chapter 2")

        try AccessibilityActions.performCustomAction(named: "Restart chapter", on: bar)

        let deadline = Date().addingTimeInterval(5)
        while (try? progressPercent()).map({ $0 > 2 }) ?? true, Date() < deadline {
            usleep(100_000)
        }
        XCTAssertLessThanOrEqual(try progressPercent(), 2, "Restart chapter did not go back to its start")
        XCTAssertTrue(bar.label.contains("Chapter 2"), "restart is not previous chapter: \"\(bar.label)\"")
    }

    /// The play/pause buttons say which they are (labelled in #144): the bar's, a row's
    /// and the details screen's, which share `PlayButtonView`. Either may show while the audio
    /// starts, so this checks for a label; `loadPlayableBook` checks it flips.
    func test_a11y_playPause_isLabelled() throws {
        try loadSeededBook(titled: "Seeded Chaptered Book")
        let labels: Set<String> = ["Play", "Pause"]

        let barButton = element(AccessibilityID.MiniPlayer.playPause).label
        XCTAssertTrue(labels.contains(barButton), "the bar's play button reads \"\(barButton)\"")
        let rowButton = element(AccessibilityID.Element.play(AccessibilityID.Library.row(0))).label
        XCTAssertTrue(labels.contains(rowButton), "a row's play button reads \"\(rowButton)\"")
        openFromBar()
        XCTAssertTrue(labels.contains(transportPlay.label), "the transport's play button reads \"\(transportPlay.label)\"")
    }

    // MARK: - The progress line

    func test_a11y_progress_hasLabelAndPercentValue() throws {
        try loadSeededBook(titled: "Seeded Chaptered Book")

        XCTAssertEqual(progress.label, "Chapter progress")
        XCTAssertEqual(progress.value as? String, "0%")
    }

    func test_a11y_progress_valueIsTheChapterFraction() throws {
        try loadPlayableBook()

        XCTAssertEqual(progress.label, "Chapter progress")
        // 200 s into chapter 2 (144.0 to 288.0 s) is 38.9%; the pause lands a moment later.
        XCTAssertEqual(try progressPercent(), 39, accuracy: 2, "\(String(describing: progress.value))")
        XCTAssertTrue((progress.value as? String)?.hasSuffix("%") ?? false, "\(String(describing: progress.value))")
    }

    // MARK: - The details screen

    func test_a11y_closeChevron_isLabelled_andActivateCollapses() throws {
        try loadSeededBook(titled: "Seeded Chaptered Book")
        let before = restingFrame(of: bar)
        openFromBar()
        let close = element(AccessibilityID.Player.close)
        XCTAssertEqual(close.label, "Close player")

        try AccessibilityActions.activate(close)

        assertCollapsedIntoBar(restingAt: before)
    }

    /// The two-finger scrub, sent from inside the details screen as VoiceOver would from whatever
    /// it has focused: it walks up to the panel's escape action, which closes it.
    func test_a11y_escape_closesDetails() throws {
        try loadSeededBook(titled: "Seeded Chaptered Book")
        let before = restingFrame(of: bar)
        openFromBar()

        try AccessibilityActions.escape(from: element(AccessibilityID.Player.title))

        assertCollapsedIntoBar(restingAt: before)
    }

    // MARK: - Reduce Motion

    /// With Reduce Motion the panel is full-screen at every progress and only its opacity moves.
    /// Open and close still land, and once closed nothing invisible is left over the tabs: the
    /// bar and a library row both take touches.
    func test_a11y_reduceMotion_opensAndCloses_andTouchesReachTheLibrary() throws {
        try loadSeededBook(
            titled: "Seeded Chaptered Book",
            arguments: [LaunchArgument.seedLibrary, LaunchArgument.forceReduceMotion]
        )
        let before = restingFrame(of: bar)
        openFromBar()
        XCTAssertTrue(transportPlay.isHittable, "the open details screen does not take touches")

        element(AccessibilityID.Player.close).tap()

        assertCollapsedIntoBar(restingAt: before)
        let plainIndex = try XCTUnwrap(rowIndex(titled: "Seeded Plain Book"))
        let plainTitle = element(AccessibilityID.Element.title(AccessibilityID.Library.row(plainIndex)))
        XCTAssertTrue(plainTitle.isHittable, "a library row is covered after the close")
        plainTitle.tap()
        XCTAssertTrue(transportPlay.waitForExistence(timeout: 10), "the tap on a row did not reach it")
        XCTAssertEqual(element(AccessibilityID.Player.title).label, "Seeded Plain Book")
    }

    /// The drags with Reduce Motion: up past 30% opens, down by the grabber collapses, and a
    /// short drag settles back closed with the bar taking touches again.
    func test_a11y_reduceMotion_dragsOpenCollapseAndSettle() throws {
        try loadSeededBook(
            titled: "Seeded Chaptered Book",
            arguments: [LaunchArgument.seedLibrary, LaunchArgument.forceReduceMotion]
        )
        let before = restingFrame(of: bar)
        let barCenter = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))

        barCenter.press(
            forDuration: 0.1,
            thenDragTo: barCenter.withOffset(CGVector(dx: 0, dy: -120)),
            withVelocity: 150,
            thenHoldForDuration: 0.5
        )
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertFalse(transportPlay.exists, "a 120 pt drag must not open the details screen")
        XCTAssertTrue(bar.isHittable, "the bar must take touches again once the expansion settled closed")
        XCTAssertTrue(element(AccessibilityID.MiniPlayer.playPause).isHittable, "the bar's play button is covered")

        barCenter.press(forDuration: 0.1, thenDragTo: top)
        XCTAssertTrue(transportPlay.waitForExistence(timeout: 10), "the drag up did not open the details screen")
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "not settled open")

        grabberCenter().press(forDuration: 0.1, thenDragTo: bottom)
        assertCollapsedIntoBar(restingAt: before)
    }
}
