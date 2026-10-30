//
//  ReadAlongUITests.swift
//  AbbayUITests
//

import XCTest

/// The player's Text pill and read-along square (#192). `-seedReadAlong` turns Read-along on and
/// swaps the speech engine for a stub that writes "Seeded line N of the read-along text" every 4 s
/// of book time (words 0.5 s apart), into a transcript store of its own that starts empty. The
/// playable seed (`-seedPlayableBook`) is saved 200 s in, so its first line is line 51 at 3:20.
///
/// Read-along needs iOS 26's speech engine: below it there is no pill, and these tests skip.
/// Tests that play pause again at the end: the seed makes sound.
final class ReadAlongUITests: XCTestCase {
    var app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard #available(iOS 26, *) else {
            throw XCTSkip("Read-along needs iOS 26")
        }
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: - Helpers

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    var transportPlay: XCUIElement {
        element(AccessibilityID.Player.transport(AccessibilityID.Transport.play))
    }

    var square: XCUIElement { element(AccessibilityID.Player.readAlong) }

    /// `hideControlsAfter`: seconds before the read-along controls hide with no interaction. Long by
    /// default, so a slow step never finds a control gone; the auto-hide tests pass 6 s (the real
    /// 3 s ran out before XCUITest finished checking the controls were there; 3 s is unit-tested).
    func launch(readAlong: Bool = true, hideControlsAfter: Int = 600, _ extra: [String] = []) {
        app.launchArguments = [
            LaunchArgument.seedLibrary,
            LaunchArgument.seedPlayableBook,
            LaunchArgument.resetSettings,
            LaunchArgument.readAlongControlsHideAfter,
            String(hideControlsAfter)
        ] + (readAlong ? [LaunchArgument.seedReadAlong] : []) + extra
        app.launch()
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 20), "no library")
    }

    /// Row order isn't insertion order: find the playable seed by title.
    private func playableRowTitle() throws -> XCUIElement {
        for index in 0..<6 {
            let candidate = element(AccessibilityID.Element.title(AccessibilityID.Library.row(index)))
            if candidate.exists, candidate.label == "Seeded Playable Book" { return candidate }
        }
        throw XCTSkip("no playable seed (the Debug fixture's audio is missing)")
    }

    /// Opens the playable seed without playing it, and waits for the player to settle at the top.
    func openPlayableBook(file: StaticString = #filePath, line: UInt = #line) throws {
        try playableRowTitle().tap()
        let close = element(AccessibilityID.Player.close)
        XCTAssertTrue(close.waitForExistence(timeout: 15), "the player did not open", file: file, line: line)
        let deadline = Date().addingTimeInterval(5)
        while close.frame.minY > app.frame.height / 4, Date() < deadline {
            usleep(100_000)
        }
        XCTAssertTrue(transportPlay.waitForExistence(timeout: 5), file: file, line: line)
    }

    /// Taps the Text pill and waits for the square and its first line.
    func showText(file: StaticString = #filePath, line: UInt = #line) {
        let pill = element(AccessibilityID.Player.text)
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "no Text pill", file: file, line: line)
        pill.tap()
        XCTAssertTrue(square.waitForExistence(timeout: 5), "the square did not show the text", file: file, line: line)
        XCTAssertTrue(
            element(AccessibilityID.Player.readAlongLine(0)).waitForExistence(timeout: 10),
            "no first line",
            file: file,
            line: line
        )
    }

    func waitForLabel(of element: XCUIElement, _ label: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.label != label, Date() < deadline {
            usleep(100_000)
        }
        return element.label == label
    }

    /// Plays from the player's transport, and pauses again when the test ends.
    func play(file: StaticString = #filePath, line: UInt = #line) {
        transportPlay.tap()
        XCTAssertTrue(waitForLabel(of: transportPlay, "Pause"), "did not start playing", file: file, line: line)
        addTeardownBlock { [transportPlay] in
            if transportPlay.exists, transportPlay.label == "Pause" { transportPlay.tap() }
        }
    }

    /// The read-along lines on screen that carry the selected trait.
    private func selectedLines() -> [XCUIElement] {
        let prefix = String(AccessibilityID.Player.readAlongLine(0).dropLast())
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByIndex
            .filter(\.isSelected)
    }

    private func lineIndex(of line: XCUIElement) -> Int? {
        let prefix = String(AccessibilityID.Player.readAlongLine(0).dropLast())
        return Int(line.identifier.dropFirst(prefix.count))
    }

    /// The scrubber's elapsed label ("3:40"), in seconds. The remaining one has a minus sign.
    func elapsedSeconds() -> Int? {
        let label = app.staticTexts
            .matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+:[0-9]{2}$"))
            .firstMatch
        guard label.exists else { return nil }
        let parts = label.label.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    // MARK: - The pill

    func test_pill_absentWhenReadAlongOff() throws {
        launch(readAlong: false)
        try openPlayableBook()

        XCTAssertTrue(element(AccessibilityID.Player.speed).exists, "the pill row is there")
        XCTAssertFalse(element(AccessibilityID.Player.text).exists, "a Text pill with Read-along off")
        XCTAssertFalse(square.exists)
    }

    func test_pill_flipsCoverToText_andBack() throws {
        launch()
        try openPlayableBook()

        showText()
        element(AccessibilityID.Player.text).tap()

        XCTAssertTrue(square.waitForNonExistence(timeout: 5), "the second tap did not bring the cover back")
        XCTAssertFalse(element(AccessibilityID.Player.readAlongLine(0)).exists)
    }

    // MARK: - Following playback

    /// The current line moves on as the book plays: a line after the first gets the selected trait.
    func test_text_followsPlayback() throws {
        launch()
        try openPlayableBook()
        showText()

        play()

        let deadline = Date().addingTimeInterval(15)
        var moved: XCUIElement?
        while moved == nil, Date() < deadline {
            moved = selectedLines().first { line in
                (lineIndex(of: line) ?? 0) > 0 && line.label.contains("Seeded line")
            }
            if moved == nil { usleep(250_000) }
        }
        XCTAssertNotNil(moved, "the highlight never moved past the first line")
    }

    // MARK: - Tapping a line

    /// A line seeks when tapped, so VoiceOver gets it as a button (its hint, "Plays from this line",
    /// is checked in `ReadAlongViewTests`).
    func test_lines_areButtons() throws {
        launch()
        try openPlayableBook()
        showText()

        XCTAssertTrue(app.buttons[AccessibilityID.Player.readAlongLine(0)].waitForExistence(timeout: 5))
    }

    /// Review Focus 3: the shown book isn't loaded, so a line tap must not load or play it.
    func test_lineTap_onABookNotLoaded_doesNotStartPlayback() throws {
        launch()
        try openPlayableBook()
        showText()
        XCTAssertEqual(transportPlay.label, "Play")

        let line = element(AccessibilityID.Player.readAlongLine(1))
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        line.tap()

        sleep(2)
        XCTAssertEqual(transportPlay.label, "Play", "a line tap started playback")
        XCTAssertFalse(element(AccessibilityID.MiniPlayer.bar).exists, "a line tap loaded the book")
    }

    /// On the loaded book a line tap seeks to the line's start: the scrubber's elapsed time jumps
    /// there (line N starts at (N − 1) × 4 s).
    func test_lineTap_onLoadedBook_seeks() throws {
        launch()
        try openPlayableBook()
        showText()
        play()

        let line = element(AccessibilityID.Player.readAlongLine(5))
        XCTAssertTrue(line.waitForExistence(timeout: 5), "no sixth line")
        let number = try XCTUnwrap(
            line.label.split(separator: " ").dropFirst(2).first.flatMap { Int($0) },
            "unexpected line text \"\(line.label)\""
        )
        let start = (number - 1) * 4
        line.tap()

        let deadline = Date().addingTimeInterval(5)
        var elapsed = elapsedSeconds()
        while !(elapsed.map { $0 >= start && $0 <= start + 3 } ?? false), Date() < deadline {
            usleep(100_000)
            elapsed = elapsedSeconds()
        }
        let landed = try XCTUnwrap(elapsed, "no elapsed label")
        XCTAssertTrue(landed >= start && landed <= start + 3, "elapsed \(landed) s, line starts at \(start) s")
    }

    // MARK: - Language

    func test_languageMenu_listsLanguages() throws {
        launch()
        try openPlayableBook()
        showText()

        let label = element(AccessibilityID.Player.readAlongLanguage)
        XCTAssertTrue(label.waitForExistence(timeout: 5), "no language label")
        XCTAssertEqual(label.value as? String, "English", "the label names the detected language")
        label.tap()

        XCTAssertTrue(app.buttons["English"].waitForExistence(timeout: 5), "the menu doesn't list English")
        XCTAssertTrue(app.buttons["Portuguese"].exists, "the menu doesn't list Portuguese")
    }

    /// The chapter panel floats over the square: the language label stays where it is, under the
    /// panel, rather than drawing over the chapters or stepping aside (owner's device tests: in the
    /// player's glass container it drew over the panel, and when it was taken out instead the
    /// panel's glass morphed out of the square's buttons). A tap there reaches the panel, not the
    /// label; once the panel closes, the label works.
    func test_languageLabel_staysUnderTheChapterPanel() throws {
        launch()
        try openPlayableBook()
        showText()

        let label = element(AccessibilityID.Player.readAlongLanguage)
        XCTAssertTrue(label.waitForExistence(timeout: 5), "no language label")
        let before = label.frame
        element(AccessibilityID.Player.chapters).tap()
        XCTAssertTrue(element(AccessibilityID.Player.chaptersTitle).waitForExistence(timeout: 5), "no chapter panel")
        sleep(1)
        // Still there and in place under the panel, but disabled while the panel covers it (and
        // hidden from VoiceOver, which XCUITest can't observe).
        XCTAssertTrue(label.exists, "the language label stepped aside")
        XCTAssertEqual(label.frame, before, "the language label moved")
        XCTAssertFalse(label.isEnabled, "the language label can be used behind the chapter panel")
        // Tap where it is drawn: the panel takes the tap, and the label's menu doesn't open.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: before.midX, dy: before.midY)).tap()
        XCTAssertFalse(
            app.buttons["English"].waitForExistence(timeout: 2), "the language label is over the chapter panel"
        )
        XCTAssertTrue(element(AccessibilityID.Player.chaptersTitle).exists, "the tap didn't land on the panel")

        element(AccessibilityID.Player.chapters).tap()
        XCTAssertTrue(element(AccessibilityID.Player.chaptersTitle).waitForNonExistence(timeout: 5))
        let enabled = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: label)
        wait(for: [enabled], timeout: 5)
        sleep(1) // the panel's close animation takes taps until it's gone
        label.tap()
        XCTAssertTrue(app.buttons["English"].waitForExistence(timeout: 5), "the label lost its menu")
    }

    // MARK: - Reduce Motion, reopening, landscape

    func test_reduceMotion_stillShowsCurrentLine() throws {
        launch([LaunchArgument.forceReduceMotion])
        try openPlayableBook()
        showText()

        let deadline = Date().addingTimeInterval(5)
        while selectedLines().isEmpty, Date() < deadline {
            usleep(200_000)
        }
        XCTAssertEqual(selectedLines().count, 1, "one current line, with Reduce Motion too")
    }

    /// Whether the text or the cover shows is remembered app-wide.
    func test_textStaysUp_acrossReopen() throws {
        launch()
        try openPlayableBook()
        showText()

        element(AccessibilityID.Player.close).tap()
        XCTAssertTrue(square.waitForNonExistence(timeout: 10), "the player did not close")
        try openPlayableBook()

        XCTAssertTrue(square.waitForExistence(timeout: 5), "the text did not stay up")
    }

    /// The square is rebuilt by a flip and by a rotation, but the session isn't: the text comes
    /// straight back, with no *Preparing text…* in between.
    func test_flipAndRotation_bringTheTextStraightBack() throws {
        launch()
        try openPlayableBook()
        showText()
        let pill = element(AccessibilityID.Player.text)
        let firstLine = element(AccessibilityID.Player.readAlongLine(0))
        let status = element(AccessibilityID.Player.readAlongStatus)

        pill.tap()
        XCTAssertTrue(square.waitForNonExistence(timeout: 5))
        pill.tap()
        XCTAssertTrue(firstLine.waitForExistence(timeout: 2), "the text didn't come back")
        XCTAssertFalse(status.exists, "the text was prepared again after a flip")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(firstLine.waitForExistence(timeout: 5), "the text didn't survive the rotation")
        XCTAssertFalse(status.exists, "the text was prepared again after a rotation")
    }

    /// Landscape (#270) puts the cover on the leading side; the text takes its place there.
    func test_landscape_textTakesTheCoversPlace() throws {
        launch()
        try openPlayableBook()
        showText()

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)

        XCTAssertTrue(square.waitForExistence(timeout: 5), "the text is gone in landscape")
        XCTAssertTrue(transportPlay.exists)
        XCTAssertLessThan(square.frame.minX, transportPlay.frame.minX, "the text isn't on the leading side")
        XCTAssertLessThanOrEqual(square.frame.maxX, transportPlay.frame.minX, "the text overlaps the controls")
    }
}
