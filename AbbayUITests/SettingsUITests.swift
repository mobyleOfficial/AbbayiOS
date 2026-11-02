//
//  SettingsUITests.swift
//  AbbayUITests
//

import Speech
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
    ///
    /// `stubEngine` gives Read-along an engine where the real one doesn't run (the Simulator), so
    /// the Experimental section is drawn; the switch stays off.
    private func launch(language: String = "en", locale: String = "en_US", stubEngine: Bool = false) {
        app.launchArguments = [
            LaunchArgument.seedLibrary,
            LaunchArgument.resetSettings,
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ] + (stubEngine ? [LaunchArgument.stubReadAlongEngine] : [])
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
        // iOS 27.1 (seen on the iPhone Duo) hides the navigation bar's items while the form is
        // scrolled down: the bar stays, Done leaves the tree. Scroll back up to bring it back. A
        // swipe that starts scrolled never dismisses the sheet, and the loop stops at the top.
        let done = element(AccessibilityID.Settings.done)
        for _ in 0..<4 where !done.waitForExistence(timeout: 1) {
            app.swipeDown()
        }
        done.tap()
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
    /// onto a line of its own under the label (#189): a row nearly twice its neighbour's height.
    /// Now the value stays beside the label; on the narrowest phone a long label may wrap, which
    /// adds one line of text, not a line for the value. VoiceOver reads it as label and value.
    func test_cellularPicker_keepsItsValueBesideTheLabel() {
        let cases = [
            ("pt-BR", "pt_BR", "Downloads grandes no celular", "Perguntar"),
            ("en", "en_US", "Large downloads on cellular", "Ask")
        ]
        for (language, locale, label, value) in cases {
            launch(language: language, locale: locale)
            openSettings()
            let row = element(AccessibilityID.Settings.cellular)
            for _ in 0..<4 where !(row.exists && row.isHittable) {
                app.swipeUp()
            }
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            let neighbour = element(AccessibilityID.Settings.spaceUsed)
            XCTAssertTrue(neighbour.waitForExistence(timeout: 15))

            XCTAssertEqual(row.label, label)
            XCTAssertEqual(row.value as? String, value)
            XCTAssertLessThan(
                row.frame.height,
                neighbour.frame.height * 1.5,
                "\(language): the cellular row (\(row.frame)) is much taller than Space used (\(neighbour.frame))"
            )
        }
    }

    /// The row is a `Menu` holding the picker (#189): a tap anywhere on it lists the options, and
    /// choosing one becomes its value.
    func test_cellularPicker_choosingAnOption_becomesItsValue() {
        launch()
        openSettings()
        let row = element(AccessibilityID.Settings.cellular)
        for _ in 0..<4 where !(row.exists && row.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 15))

        row.tap()
        let wifiOnly = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Wi-Fi only"))
        XCTAssertTrue(wifiOnly.firstMatch.waitForExistence(timeout: 5), "the options did not open")
        wifiOnly.firstMatch.tap()

        let chosen = NSPredicate(format: "value == %@", "Wi-Fi only")
        let expectation = XCTNSPredicateExpectation(predicate: chosen, object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, "value: \(String(describing: row.value))")
    }

    func test_gear_opensSettings_withEverySection_andDoneCloses() {
        launch(stubEngine: true)

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
        // Scrolled to each in turn: the form is longer than the screen, and rows scrolled far off
        // leave the tree.
        var identifiers = [AccessibilityID.Settings.language(AppLanguageRaw.system)]
        if #available(iOS 26, *) {
            identifiers += [AccessibilityID.Settings.readAlong, AccessibilityID.Settings.findChapters]
        }
        identifiers += [
            AccessibilityID.Settings.privacyPolicy,
            AccessibilityID.Settings.version,
            AccessibilityID.Settings.librivox,
            AccessibilityID.Settings.licenses,
            AccessibilityID.Settings.audioStatus
        ]
        for identifier in identifiers {
            let row = element(identifier)
            for _ in 0..<6 where !(row.exists && row.isHittable) { app.swipeUp() }
            assertResolves(identifier)
        }

        closeSettings()
        assertResolves(AccessibilityID.Library.list)
    }

    // MARK: - Experimental

    /// The Experimental section exists only where the speech engine runs (iOS 26, on hardware
    /// Speech transcribes on): the stub engine stands in for it in the Simulator.
    private func openExperimental(language: String = "en", locale: String = "en_US") throws {
        guard #available(iOS 26, *) else { throw XCTSkip("Read-along needs iOS 26") }
        launch(language: language, locale: locale, stubEngine: true)
        openSettings()
        let toggle = element(AccessibilityID.Settings.readAlong)
        for _ in 0..<6 where !(toggle.exists && toggle.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), "no Read-along switch")
    }

    /// Where Speech can't transcribe (the Simulator) there is no engine, so no section: not a switch
    /// that turns on a feature that can only say "Text isn't available".
    func test_experimental_absentWhereTheEngineDoesNotRun() throws {
        if #available(iOS 26, *), SpeechTranscriber.isAvailable {
            throw XCTSkip("the speech engine runs here")
        }
        launch()
        openSettings()
        for _ in 0..<4 { app.swipeUp() }

        assertResolves(AccessibilityID.Settings.audioStatus)
        XCTAssertFalse(element(AccessibilityID.Settings.readAlong).exists, "a Read-along switch with no engine")
    }

    func test_experimental_readAlong_offByDefault() throws {
        try openExperimental()

        XCTAssertEqual(value(of: AccessibilityID.Settings.readAlong), "0")
    }

    func test_experimental_readAlong_toggles() throws {
        try openExperimental()
        let toggle = element(AccessibilityID.Settings.readAlong)

        // The row spans the form; its switch sits at the trailing edge, where a tap lands on it.
        for expected in ["1", "0"] {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            let changed = NSPredicate(format: "value == %@", expected)
            let waiter = XCTNSPredicateExpectation(predicate: changed, object: toggle)
            XCTAssertEqual(XCTWaiter.wait(for: [waiter], timeout: 5), .completed, "value: \(String(describing: toggle.value))")
        }
    }

    func test_experimental_footerExplains() throws {
        let cases = [
            ("en", "en_US", "Experimental", "Read-along", "microphone"),
            ("pt-BR", "pt_BR", "Experimental", "Leitura acompanhada", "microfone")
        ]
        for (language, locale, title, label, word) in cases {
            try openExperimental(language: language, locale: locale)
            XCTAssertEqual(element(AccessibilityID.Settings.readAlong).label, label)
            let footer = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", word)).firstMatch
            XCTAssertTrue(footer.waitForExistence(timeout: 5), "\(language): no footer mentioning \"\(word)\"")
            XCTAssertTrue(
                app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", title)).firstMatch.exists,
                "\(language): no \"\(title)\" header"
            )
            app.terminate()
        }
    }

    func test_licensesPage_opens() {
        launch()
        openSettings()
        app.swipeUp()
        app.swipeUp()

        element(AccessibilityID.Settings.licenses).tap()

        assertResolves(AccessibilityID.Settings.licensesBody)
    }

    /// About the developer is a page, not a link: its title, body and button resolve. The button
    /// is not tapped, as it would open Safari.
    func test_developerPage_showsItsTitleBodyAndButton() {
        launch()
        openSettings()
        app.swipeUp()
        app.swipeUp()

        element(AccessibilityID.Settings.developer).tap()

        assertResolves(AccessibilityID.Settings.developerBody)
        assertResolves(AccessibilityID.Settings.linkedIn)
        XCTAssertTrue(app.staticTexts["About the developer"].exists, "the page title")
        XCTAssertTrue(app.buttons["Say hi on LinkedIn"].exists)
        XCTAssertTrue(element(AccessibilityID.Settings.developerBody).label.contains("no ads and no tracking"))
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
