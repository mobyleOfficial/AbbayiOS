//
//  KeyboardUITests.swift
//  AbbayUITests
//

import XCTest

/// The keyboard and the details screen. Needs a software keyboard: on a simulator with a hardware
/// keyboard connected none appears, and the test skips.
final class KeyboardUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The details screen opens over the Library in the same hierarchy as its search field: the
    /// keyboard must not stay up over the timeline and the chapters.
    func test_openingDetailsFromASearch_dismissesTheKeyboard() throws {
        app.launchArguments = [LaunchArgument.seedLibrary]
        app.launch()
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 15))
        // The Library field's placeholder (`Localizable.librarySearchPrompt`, English).
        let field = app.searchFields
            .matching(NSPredicate(format: "placeholderValue == %@", "Search your library"))
            .firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            throw XCTSkip("no software keyboard (hardware keyboard connected)")
        }
        field.typeText("Chaptered")
        let title = element(AccessibilityID.Element.title(AccessibilityID.Library.row(0)))
        XCTAssertTrue(title.waitForExistence(timeout: 15))

        title.tap()

        let play = element(AccessibilityID.Player.transport(AccessibilityID.Transport.play))
        XCTAssertTrue(play.waitForExistence(timeout: 15), "the details screen did not open")
        let keyboard = app.keyboards.firstMatch
        let deadline = Date().addingTimeInterval(5)
        while keyboard.exists, Date() < deadline {
            usleep(100_000)
        }
        XCTAssertFalse(keyboard.exists, "the keyboard stayed up over the details screen")
        XCTAssertTrue(play.isHittable, "the transport's play button is covered")
    }
}
