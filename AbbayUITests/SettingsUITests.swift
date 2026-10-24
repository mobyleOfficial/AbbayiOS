//
//  SettingsUITests.swift
//  AbbayUITests
//

import XCTest

/// The Settings sheet (from the library's gear), the skip amounts reaching the player's buttons,
/// the speed sheet, and the language switch without a relaunch. Every launch passes
/// `-resetSettings`, so settings live in memory and never leak into the next test.
final class SettingsUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Helpers

    private func launch() {
        app.launchArguments = [LaunchArgument.seedLibrary, LaunchArgument.resetSettings]
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

    private func openSettings() {
        assertResolves(AccessibilityID.Library.list)
        element(AccessibilityID.Library.toolbarSettings).tap()
        assertResolves(AccessibilityID.Settings.done)
    }

    private func closeSettings() {
        element(AccessibilityID.Settings.done).tap()
        XCTAssertTrue(element(AccessibilityID.Settings.done).waitForNonExistence(timeout: 10), "Settings did not close")
    }

    private func rowIndex(titled title: String, maxRows: Int = 4) -> Int? {
        for index in 0..<maxRows {
            let candidate = element(AccessibilityID.Element.title(AccessibilityID.Library.row(index)))
            if candidate.exists, candidate.label == title {
                return index
            }
        }
        return nil
    }

    /// Opens the details screen for a seeded book and waits for it to slide in.
    private func openPlayer() throws {
        assertResolves(AccessibilityID.Library.list)
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Chaptered Book"))
        element(AccessibilityID.Element.title(AccessibilityID.Library.row(index))).tap()
        let close = element(AccessibilityID.Player.close)
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        let deadline = Date().addingTimeInterval(5)
        while close.frame.minY > app.frame.height / 4, Date() < deadline {
            usleep(100_000)
        }
    }

    private func value(of identifier: String) -> String? {
        element(identifier).value as? String
    }

    // MARK: - Settings screen

    func test_gear_opensSettings_withEverySection_andDoneCloses() {
        launch()

        openSettings()

        for identifier in [
            AccessibilityID.Settings.defaultSpeed,
            AccessibilityID.Settings.skipBack,
            AccessibilityID.Settings.skipForward,
            AccessibilityID.Settings.cellular,
            AccessibilityID.Settings.spaceUsed,
            AccessibilityID.Settings.deleteFinished
        ] {
            assertResolves(identifier)
        }
        let deleteFinished = element(AccessibilityID.Settings.deleteFinished)
        XCTAssertFalse(deleteFinished.isEnabled, "seeded books are not finished downloads")
        app.swipeUp()
        app.swipeUp()
        for identifier in [
            AccessibilityID.Settings.language(AppLanguageRaw.system),
            AccessibilityID.Settings.privacyPolicy,
            AccessibilityID.Settings.version,
            AccessibilityID.Settings.librivox,
            AccessibilityID.Settings.licenses,
            AccessibilityID.Settings.audioStatus
        ] {
            assertResolves(identifier)
        }

        closeSettings()
        assertResolves(AccessibilityID.Library.list)
    }

    func test_licensesPage_opens() {
        launch()
        openSettings()
        app.swipeUp()
        app.swipeUp()

        element(AccessibilityID.Settings.licenses).tap()

        assertResolves(AccessibilityID.Settings.licensesBody)
    }

    // MARK: - Skip intervals

    /// Changing the forward amount in Settings changes the player's button: its label (and its
    /// SF Symbol) carries the new number.
    func test_changingSkipForward_updatesThePlayersButton() throws {
        launch()
        openSettings()

        element(AccessibilityID.Settings.skipForward).tap()
        let option = app.buttons["30 seconds"]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "the skip menu did not open")
        option.tap()
        closeSettings()
        try openPlayer()

        let forward = element(AccessibilityID.Player.transport(AccessibilityID.Transport.forward))
        XCTAssertTrue(forward.waitForExistence(timeout: 5))
        XCTAssertEqual(forward.label, "Skip forward 30 seconds")
        XCTAssertEqual(
            element(AccessibilityID.Player.transport(AccessibilityID.Transport.back)).label,
            "Skip back 15 seconds",
            "the back amount is unchanged"
        )
    }

    // MARK: - Speed sheet

    func test_speedSheet_changesTheBooksSpeed() throws {
        launch()
        try openPlayer()
        XCTAssertEqual(value(of: AccessibilityID.Player.speed), "1.0×")

        element(AccessibilityID.Player.speed).tap()
        assertResolves(AccessibilityID.Speed.value)
        XCTAssertEqual(value(of: AccessibilityID.Speed.value), "1.0×")

        element(AccessibilityID.Speed.increase).tap()
        XCTAssertEqual(value(of: AccessibilityID.Speed.value), "1.05×")
        element(AccessibilityID.Speed.decrease).tap()
        element(AccessibilityID.Speed.decrease).tap()
        XCTAssertEqual(value(of: AccessibilityID.Speed.value), "0.95×")
        element(AccessibilityID.Speed.preset(1.5)).tap()
        XCTAssertEqual(value(of: AccessibilityID.Speed.value), "1.5×")

        app.swipeDown(velocity: .fast)
        XCTAssertTrue(element(AccessibilityID.Speed.value).waitForNonExistence(timeout: 10), "the sheet did not close")
        XCTAssertEqual(value(of: AccessibilityID.Player.speed), "1.5×", "the player's button shows the book's speed")
    }

    func test_speedSheet_setAsDefault_disablesItselfForThatSpeed() throws {
        launch()
        try openPlayer()
        element(AccessibilityID.Player.speed).tap()
        assertResolves(AccessibilityID.Speed.setDefault)
        let setDefault = element(AccessibilityID.Speed.setDefault)
        XCTAssertFalse(setDefault.isEnabled, "1.0× already is the default")

        element(AccessibilityID.Speed.preset(2)).tap()
        XCTAssertTrue(setDefault.isEnabled)
        setDefault.tap()

        XCTAssertFalse(setDefault.isEnabled)
        XCTAssertEqual(setDefault.label, "This is the default for new books")
    }

    // MARK: - Language

    /// Picking Português switches the open Settings screen and, after closing it, the tabs,
    /// without a relaunch.
    func test_choosingPortuguese_appliesWithoutRelaunch() {
        launch()
        openSettings()
        app.swipeUp()

        element(AccessibilityID.Settings.language(AppLanguageRaw.portuguese)).tap()

        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 5), "Settings did not switch language")
        closeSettings()
        let library = app.navigationBars["Biblioteca"]
        XCTAssertTrue(library.waitForExistence(timeout: 5), "the library did not switch language")
    }
}

/// `AppLanguage` raw values. The UI test target cannot import the app, so the two it needs are
/// spelled here; `AppSettingsTests` pins the enum on the app side.
private enum AppLanguageRaw {
    static let system = "system"
    static let portuguese = "portuguese"
}
