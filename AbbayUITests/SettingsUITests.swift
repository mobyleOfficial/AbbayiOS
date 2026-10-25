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

    /// English with a US region, so labels ("30 seconds") and speeds ("1.5×", not "1,5×") don't
    /// depend on the simulator's region.
    private func launch(language: String = "en", locale: String = "en_US") {
        app.launchArguments = [
            LaunchArgument.seedLibrary,
            LaunchArgument.resetSettings,
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ]
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

    /// pt-BR's cellular label was too long for its row, and the menu picker then dropped its value
    /// under the label (#189). The value must stay on the trailing side, in both languages.
    func test_cellularPicker_keepsItsValueBesideTheLabel() {
        for (language, locale) in [("pt-BR", "pt_BR"), ("en", "en_US")] {
            launch(language: language, locale: locale)
            openSettings()
            let picker = element(AccessibilityID.Settings.cellular)
            for _ in 0..<4 where !(picker.exists && picker.isHittable) {
                app.swipeUp()
            }
            XCTAssertTrue(picker.waitForExistence(timeout: 15))

            XCTAssertGreaterThan(
                picker.frame.minX,
                app.frame.midX,
                "\(language): the value is not on the trailing side (\(picker.frame))"
            )
        }
    }

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

    /// #179: on a Portuguese device, switching to English re-reads the skip pickers' selected
    /// value at once ("15 seconds"), like every other string on the sheet.
    func test_switchingLanguage_relabelsTheSkipPickers() {
        launch(language: "pt-BR", locale: "pt_BR")
        openSettings()
        XCTAssertTrue(skipPickerText(AccessibilityID.Settings.skipBack).contains("15 segundos"))
        app.swipeUp()

        element(AccessibilityID.Settings.language(AppLanguageRaw.english)).tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Settings did not switch language")
        app.swipeDown()
        for identifier in [AccessibilityID.Settings.skipBack, AccessibilityID.Settings.skipForward] {
            assertResolves(identifier)
            let text = skipPickerText(identifier)
            XCTAssertTrue(text.contains("15 seconds"), "\(identifier) reads \"\(text)\"")
            XCTAssertFalse(text.contains("segundos"), "\(identifier) reads \"\(text)\"")
        }
    }

    /// A menu picker's label and selected value, however SwiftUI splits them between the
    /// element's label and value.
    private func skipPickerText(_ identifier: String) -> String {
        let picker = element(identifier)
        return [picker.label, picker.value as? String ?? ""].joined(separator: " | ")
    }
}

/// `AppLanguage` raw values. The UI test target cannot import the app, so the ones it needs are
/// spelled here; `AppSettingsTests` pins the enum on the app side.
private enum AppLanguageRaw {
    static let system = "system"
    static let english = "english"
    static let portuguese = "portuguese"
}
