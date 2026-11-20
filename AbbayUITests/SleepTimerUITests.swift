//
//  SleepTimerUITests.swift
//  AbbayUITests
//

import XCTest

/// The sleep timer's moon on the player (#332): a tap offers the choices, a running timer counts
/// down on the pill, then fades the book out and pauses it. `-sleepTimerSeconds 8` makes *5 minutes*
/// last 8 seconds. Every launch passes `-resetSettings`, so nothing leaks between tests.
final class SleepTimerUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = [
            LaunchArgument.seedLibrary,
            LaunchArgument.resetSettings,
            LaunchArgument.sleepTimerSeconds, "8",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ] + extra
        app.launch()
    }

    // MARK: - Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var pill: XCUIElement { element(AccessibilityID.Player.sleepTimer) }

    private var playButton: XCUIElement {
        element(AccessibilityID.Player.transport(AccessibilityID.Transport.play))
    }

    private func openPlayer(_ title: String) throws {
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 15))
        var index: Int?
        for candidate in 0..<6 {
            let cell = element(AccessibilityID.Element.title(AccessibilityID.Library.row(candidate)))
            if cell.exists, cell.label == title {
                index = candidate
                break
            }
        }
        let row = try XCTUnwrap(index, "no \(title) in the library")
        element(AccessibilityID.Element.title(AccessibilityID.Library.row(row))).tap()
        let close = element(AccessibilityID.Player.close)
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        let deadline = Date().addingTimeInterval(5)
        while close.frame.minY > app.frame.height / 4, Date() < deadline {
            usleep(100_000)
        }
    }

    private func wait(for element: XCUIElement, _ format: String, _ value: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format, value), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func choose(_ title: String) {
        pill.tap()
        let option = app.buttons[title]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "the menu has no \(title)")
        option.tap()
    }

    // MARK: - Tests

    func test_sleepTimer_countsDown_thenPausesTheBook() throws {
        launch()
        try openPlayer("Seeded Chaptered Book")
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertEqual(pill.label, "Sleep timer")
        XCTAssertEqual(pill.value as? String, "Off")

        playButton.tap()
        XCTAssertTrue(wait(for: playButton, "label == %@", "Pause", timeout: 10), "not playing")
        choose("5 minutes")

        XCTAssertTrue(
            wait(for: pill, "value == %@", "Less than a minute left", timeout: 5),
            "running: \(String(describing: pill.value))"
        )
        XCTAssertTrue(wait(for: playButton, "label == %@", "Play", timeout: 20), "the timer didn't pause the book")
        XCTAssertTrue(wait(for: pill, "value == %@", "Off", timeout: 5))
    }

    func test_sleepTimer_holdsWhilePaused() throws {
        launch()
        try openPlayer("Seeded Chaptered Book")
        playButton.tap()
        XCTAssertTrue(wait(for: playButton, "label == %@", "Pause", timeout: 10), "not playing")
        choose("5 minutes")
        playButton.tap()
        XCTAssertTrue(wait(for: playButton, "label == %@", "Play", timeout: 5))

        sleep(12)

        XCTAssertEqual(pill.value as? String, "Less than a minute left", "a pause holds the count")
    }

    func test_sleepTimer_offersEndOfChapter_onlyWithChapters() throws {
        launch()
        try openPlayer("Seeded Chaptered Book")
        pill.tap()
        XCTAssertTrue(app.buttons["When current chapter ends"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["1 hour"].exists)
        XCTAssertTrue(app.buttons["Off"].exists)
        app.buttons["Off"].tap()
        XCTAssertEqual(pill.value as? String, "Off")

        app.terminate()
        launch()
        try openPlayer("Seeded Plain Book")
        pill.tap()
        XCTAssertTrue(app.buttons["5 minutes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["When current chapter ends"].exists, "a book with no chapters has no chapter end")
    }

    func test_sleepTimer_endOfChapter_showsOnThePill() throws {
        launch()
        try openPlayer("Seeded Chaptered Book")
        choose("When current chapter ends")

        XCTAssertTrue(wait(for: pill, "value == %@", "When current chapter ends", timeout: 5))
    }

    /// With Read-along on the row holds five pills: none overlaps, and all stay on screen.
    func test_sleepTimer_pillsFit_withReadAlongOn() throws {
        launch([LaunchArgument.seedReadAlong])
        try openPlayer("Seeded Chaptered Book")
        playButton.tap()
        choose("1 hour")
        XCTAssertTrue(
            wait(for: pill, "value == %@", "60 minutes left", timeout: 5),
            "running: \(String(describing: pill.value)), menu open: \(app.buttons["1 hour"].exists)"
        )

        let ids = [
            AccessibilityID.Player.speed, AccessibilityID.Player.volume, AccessibilityID.Player.sleepTimer,
            AccessibilityID.Player.text, AccessibilityID.Player.chapters
        ]
        let frames = ids.map { element($0).frame }
        for (id, frame) in zip(ids, frames) {
            XCTAssertTrue(element(id).exists, "\(id) is missing")
            XCTAssertTrue(app.frame.contains(frame), "\(id) runs off screen: \(frame)")
        }
        for first in frames.indices {
            for second in frames.indices where second > first {
                XCTAssertFalse(
                    frames[first].insetBy(dx: 1, dy: 1).intersects(frames[second]),
                    "\(ids[first]) overlaps \(ids[second])"
                )
            }
        }
    }


    /// The bottom choice lies over the Chapters pill: on iOS 27 a `Menu` there lost its taps to the
    /// pill's interactive glass. Tapped low and right, where that pill is.
    func test_sleepTimer_lastChoice_overTheChaptersPill_sets() throws {
        launch()
        try openPlayer("Seeded Chaptered Book")
        pill.tap()
        let option = app.buttons["1 hour"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))

        option.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.7)).tap()

        XCTAssertTrue(
            wait(for: pill, "value == %@", "60 minutes left", timeout: 5),
            "the tap didn't reach the choice: \(String(describing: pill.value))"
        )
    }


    // MARK: - Back to where you fell asleep (#332 part 2)

    private var returnPrompt: XCUIElement { element(AccessibilityID.Player.sleepReturnGo) }

    /// `-seedSleepReturn`: *Seeded Chaptered Book* (at 0:00) was stopped by a timer at 2:30, and the
    /// listener was last awake at 1:00.
    func test_sleepReturn_seededSpot_showsAndGoesBack() throws {
        launch([LaunchArgument.seedSleepReturn])
        try openPlayer("Seeded Chaptered Book")
        XCTAssertTrue(returnPrompt.waitForExistence(timeout: 5), "no prompt for the seeded spot")
        XCTAssertTrue(returnPrompt.label.contains("Back to where you fell asleep"), returnPrompt.label)
        XCTAssertTrue(returnPrompt.label.contains("1:00"), returnPrompt.label)
        XCTAssertTrue(app.staticTexts["0:00"].exists)

        returnPrompt.tap()

        XCTAssertTrue(app.staticTexts["1:00"].waitForExistence(timeout: 5), "the book didn't go back to 1:00")
        XCTAssertFalse(returnPrompt.exists, "the prompt stayed")
        XCTAssertEqual(playButton.label, "Play", "going back doesn't start playback")
    }

    func test_sleepReturn_dismiss() throws {
        launch([LaunchArgument.seedSleepReturn])
        try openPlayer("Seeded Chaptered Book")
        XCTAssertTrue(returnPrompt.waitForExistence(timeout: 5))

        element(AccessibilityID.Player.sleepReturnDismiss).tap()

        XCTAssertTrue(wait(for: returnPrompt, "exists == %@", "0", timeout: 5) || !returnPrompt.exists)
        XCTAssertFalse(returnPrompt.exists)
        XCTAssertTrue(app.staticTexts["0:00"].exists, "dismissing doesn't move the book")
    }

    func test_sleepReturn_afterATimerPause() throws {
        launch()
        try openPlayer("Seeded Chaptered Book")
        playButton.tap()
        XCTAssertTrue(wait(for: playButton, "label == %@", "Pause", timeout: 10), "not playing")
        choose("5 minutes")
        XCTAssertTrue(wait(for: playButton, "label == %@", "Play", timeout: 20), "the timer didn't pause the book")

        XCTAssertTrue(returnPrompt.waitForExistence(timeout: 5), "no prompt after the timer paused the book")
        XCTAssertTrue(returnPrompt.label.contains("0:0"), "back to about where the timer was set: \(returnPrompt.label)")

        returnPrompt.tap()

        XCTAssertTrue(wait(for: returnPrompt, "exists == false", "", timeout: 5) || !returnPrompt.exists)
        XCTAssertFalse(returnPrompt.exists, "the prompt stayed after going back")
        XCTAssertEqual(playButton.label, "Play", "going back doesn't start playback")
    }

}
