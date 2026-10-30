//
//  ReadAlongImmersionUITests.swift
//  AbbayUITests
//

import XCTest

/// The read-along controls hide after 3 s with no interaction, in the square and full screen
/// (#192, owner's follow-up: "lets prioritize immersion"); a tap brings them back without seeking.
/// Part of `ReadAlongUITests`, with its seeds and helpers.
extension ReadAlongUITests {
    /// The delay these launches use: the real 3 s is gone before XCUITest, at about a second a
    /// query, has checked the controls are there at first. The other tests launch with a long one.
    private static let hideAfter = 6

    private var languageLabel: XCUIElement { element(AccessibilityID.Player.readAlongLanguage) }
    private var expandButton: XCUIElement { element(AccessibilityID.Player.readAlongExpand) }

    /// The language label and the expand button leave the square after the delay; a tap anywhere on
    /// it brings both back, and that tap only reveals: the elapsed time stays where it was.
    func test_squareControls_hideAfterIdle_andATapBringsThemBack() throws {
        launch(hideControlsAfter: Self.hideAfter)
        try openPlayableBook()
        showText()
        XCTAssertTrue(languageLabel.waitForExistence(timeout: 5), "no language label at first")
        XCTAssertTrue(expandButton.exists, "no expand button at first")

        XCTAssertTrue(languageLabel.waitForNonExistence(timeout: 15), "the language label never hid")
        XCTAssertTrue(expandButton.waitForNonExistence(timeout: 2), "the expand button never hid")
        let elapsed = elapsedSeconds()

        square.tap()

        XCTAssertTrue(languageLabel.waitForExistence(timeout: 2), "a tap didn't bring the language label back")
        XCTAssertTrue(expandButton.exists, "a tap didn't bring the expand button back")
        XCTAssertEqual(elapsedSeconds(), elapsed, "the revealing tap moved the time")
        XCTAssertTrue(languageLabel.waitForNonExistence(timeout: 15), "they didn't hide again after the tap")
    }

    /// While the controls are hidden, a tap on a line of the loaded book only brings them back; once
    /// they show, the same tap seeks.
    func test_lineTap_whileControlsHidden_onlyReveals() throws {
        launch(hideControlsAfter: Self.hideAfter)
        try openPlayableBook()
        showText()
        play()
        transportPlay.tap()
        XCTAssertTrue(waitForLabel(of: transportPlay, "Play"), "did not pause")
        XCTAssertTrue(languageLabel.waitForNonExistence(timeout: 15), "the controls never hid")
        let before = try XCTUnwrap(elapsedSeconds(), "no elapsed label")
        let line = element(AccessibilityID.Player.readAlongLine(5))
        XCTAssertTrue(line.exists, "no sixth line")
        let number = try XCTUnwrap(
            line.label.split(separator: " ").dropFirst(2).first.flatMap { Int($0) },
            "unexpected line text \"\(line.label)\""
        )
        let start = (number - 1) * 4
        XCTAssertNotEqual(before, start, "the line must start elsewhere for the test to mean anything")

        line.tap()

        XCTAssertTrue(languageLabel.waitForExistence(timeout: 2), "the tap didn't bring the controls back")
        sleep(1)
        XCTAssertEqual(elapsedSeconds(), before, "the revealing tap seeked")

        line.tap()

        let deadline = Date().addingTimeInterval(5)
        while elapsedSeconds() != start, Date() < deadline {
            usleep(100_000)
        }
        XCTAssertEqual(elapsedSeconds(), start, "a tap with the controls showing didn't seek")
    }

    /// The language menu hangs off the label: while it is open nothing hides; once it closes the
    /// delay runs again.
    func test_languageMenu_keepsTheControlsWhileOpen() throws {
        launch(hideControlsAfter: Self.hideAfter)
        try openPlayableBook()
        showText()
        if !languageLabel.exists { square.tap() }
        XCTAssertTrue(languageLabel.waitForExistence(timeout: 5), "no language label")

        languageLabel.tap()
        let english = app.buttons["English"]
        XCTAssertTrue(english.waitForExistence(timeout: 5), "the menu didn't open")
        sleep(UInt32(Self.hideAfter + 3))
        XCTAssertTrue(english.exists, "the menu closed under the user")
        XCTAssertTrue(languageLabel.exists, "the label hid with its menu open")

        element(AccessibilityID.Player.title).tap()
        XCTAssertTrue(english.waitForNonExistence(timeout: 5), "the menu didn't close")
        XCTAssertTrue(languageLabel.waitForNonExistence(timeout: 15), "the controls never hid after the menu closed")
    }

    /// Full screen: the language label, play/pause and collapse hide after the delay; a tap on the
    /// text brings all three back.
    func test_fullScreenControls_hideAfterIdle_andATapBringsThemBack() throws {
        launch(hideControlsAfter: Self.hideAfter)
        try openPlayableBook()
        showText()
        expand()
        let playPause = element(AccessibilityID.Player.readAlongPlayPause)
        let collapse = element(AccessibilityID.Player.readAlongCollapse)
        XCTAssertTrue(playPause.waitForExistence(timeout: 5), "no play/pause at first")
        XCTAssertTrue(collapse.exists, "no collapse at first")
        XCTAssertTrue(languageLabel.exists, "no language label at first")

        XCTAssertTrue(playPause.waitForNonExistence(timeout: 15), "play/pause never hid")
        XCTAssertTrue(collapse.waitForNonExistence(timeout: 2), "collapse never hid")
        XCTAssertTrue(languageLabel.waitForNonExistence(timeout: 2), "the language label never hid")

        fullScreen.tap()

        XCTAssertTrue(playPause.waitForExistence(timeout: 2), "a tap didn't bring play/pause back")
        XCTAssertTrue(collapse.exists, "a tap didn't bring collapse back")
        XCTAssertTrue(languageLabel.exists, "a tap didn't bring the language label back")
        XCTAssertEqual(playPause.label, "Play", "the revealing tap started playback")
        collapse.tap()
        XCTAssertTrue(fullScreen.waitForNonExistence(timeout: 5), "collapse didn't work after coming back")
    }
}
