//
//  ReadAlongFullScreenUITests.swift
//  AbbayUITests
//

import XCTest

/// The read-along text full screen (#192, owner's follow-up): the square's expand button, the text
/// over the whole window, its play/pause and collapse. Part of `ReadAlongUITests`, with its seeds
/// and helpers; in a file of its own to keep each file readable.
extension ReadAlongUITests {
    private var fullScreen: XCUIElement { element(AccessibilityID.Player.readAlongFullScreen) }

    /// Taps the square's expand button and waits for the full screen to settle over the window.
    private func expand(file: StaticString = #filePath, line: UInt = #line) {
        let expand = element(AccessibilityID.Player.readAlongExpand)
        XCTAssertTrue(expand.waitForExistence(timeout: 5), "no expand button", file: file, line: line)
        expand.tap()
        XCTAssertTrue(
            fullScreen.waitForExistence(timeout: 5), "the text did not go full screen", file: file, line: line
        )
        let window = app.windows.firstMatch.frame
        let deadline = Date().addingTimeInterval(3)
        while fullScreen.frame != window, Date() < deadline {
            usleep(100_000)
        }
    }

    /// The expand button shows the same text over the whole window (both panes when split), above
    /// the player and the mini player; collapse brings the square back with its text, not
    /// *Preparing text…*: it is the same session.
    func test_expand_coversTheScreen_andCollapseReturns() throws {
        launch()
        try openPlayableBook()
        showText()
        play()

        expand()

        XCTAssertEqual(fullScreen.frame, app.windows.firstMatch.frame, "the full screen doesn't cover the window")
        let inside = fullScreen.descendants(matching: .any)
        XCTAssertTrue(
            inside.matching(identifier: AccessibilityID.Player.readAlongLine(0)).firstMatch
                .waitForExistence(timeout: 2),
            "no lines full screen"
        )
        XCTAssertFalse(
            inside.matching(identifier: AccessibilityID.Player.readAlongStatus).firstMatch.exists,
            "the full screen prepared the text again"
        )
        let bar = element(AccessibilityID.MiniPlayer.bar)
        XCTAssertFalse(bar.exists && bar.isHittable, "the mini player is reachable under the full screen")
        let close = element(AccessibilityID.Player.close)
        XCTAssertFalse(close.exists && close.isHittable, "the player is reachable under the full screen")

        element(AccessibilityID.Player.readAlongCollapse).tap()

        XCTAssertTrue(fullScreen.waitForNonExistence(timeout: 5), "collapse didn't end the full screen")
        XCTAssertTrue(square.waitForExistence(timeout: 2), "the square didn't come back")
        XCTAssertTrue(element(AccessibilityID.Player.readAlongLine(0)).exists, "the square lost its text")
        XCTAssertFalse(element(AccessibilityID.Player.readAlongStatus).exists, "the text was prepared again")
    }

    /// Play/pause in the middle of the full screen's bar drives the player, as its transport does.
    func test_fullScreen_playPause_controlsPlayback() throws {
        launch()
        try openPlayableBook()
        showText()
        expand()

        let playPause = element(AccessibilityID.Player.readAlongPlayPause)
        XCTAssertTrue(playPause.waitForExistence(timeout: 5), "no play/pause full screen")
        XCTAssertEqual(playPause.label, "Play")
        playPause.tap()
        addTeardownBlock { [playPause] in
            if playPause.exists, playPause.label == "Pause" { playPause.tap() }
        }
        XCTAssertTrue(waitForLabel(of: playPause, "Pause"), "play didn't start playback")
        playPause.tap()
        XCTAssertTrue(waitForLabel(of: playPause, "Play"), "pause didn't stop playback")

        element(AccessibilityID.Player.readAlongCollapse).tap()
        XCTAssertTrue(fullScreen.waitForNonExistence(timeout: 5))
        XCTAssertEqual(transportPlay.label, "Play", "the player's transport disagrees")
    }

    /// The expand button steps aside while the chapter panel is open, like the language label, and
    /// works again once it closes.
    func test_expand_hidesWhileTheChapterPanelIsOpen() throws {
        launch()
        try openPlayableBook()
        showText()

        let expand = element(AccessibilityID.Player.readAlongExpand)
        XCTAssertTrue(expand.waitForExistence(timeout: 5), "no expand button")
        XCTAssertGreaterThan(expand.frame.midX, square.frame.midX, "not on the right")
        XCTAssertGreaterThan(expand.frame.midY, square.frame.midY, "not at the bottom")
        element(AccessibilityID.Player.chapters).tap()
        XCTAssertTrue(element(AccessibilityID.Player.chaptersTitle).waitForExistence(timeout: 5), "no chapter panel")
        // Faded and out of reach but kept in place: UI tests still list it, disabled.
        let deadline = Date().addingTimeInterval(5)
        while expand.exists, expand.isEnabled, Date() < deadline {
            usleep(100_000)
        }
        XCTAssertFalse(expand.exists && expand.isEnabled, "the expand button stays over the chapter panel")

        element(AccessibilityID.Player.chapters).tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 5), "the expand button didn't come back")
        XCTAssertTrue(expand.isEnabled, "the expand button didn't come back")
        expand.tap()
        XCTAssertTrue(fullScreen.waitForExistence(timeout: 5), "the expand button came back without its action")
    }
}
