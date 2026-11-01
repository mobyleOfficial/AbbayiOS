//
//  VolumeUITests.swift
//  AbbayUITests
//

import XCTest

/// Abbay's own volume on the player: the pill beside the speed raises a vertical glass capsule,
/// a drag on it sets the level, a tap outside closes it, and VoiceOver adjusts the pill in place.
/// Every launch passes `-resetSettings`, so the level starts at 100% and never leaks between tests.
final class VolumeUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            LaunchArgument.seedLibrary,
            LaunchArgument.resetSettings,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
    }

    // MARK: - Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func value(of identifier: String) -> String? {
        element(identifier).value as? String
    }

    /// "60%" → 60.
    private func percent(of identifier: String) throws -> Int {
        let text = try XCTUnwrap(value(of: identifier))
        return try XCTUnwrap(Int(text.replacingOccurrences(of: "%", with: "")), "not a percent: \(text)")
    }

    private func openPlayer() throws {
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 15))
        var index: Int?
        for candidate in 0..<4 {
            let title = element(AccessibilityID.Element.title(AccessibilityID.Library.row(candidate)))
            if title.exists, title.label == "Seeded Chaptered Book" {
                index = candidate
                break
            }
        }
        let row = try XCTUnwrap(index)
        element(AccessibilityID.Element.title(AccessibilityID.Library.row(row))).tap()
        let close = element(AccessibilityID.Player.close)
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        let deadline = Date().addingTimeInterval(5)
        while close.frame.minY > app.frame.height / 4, Date() < deadline {
            usleep(100_000)
        }
    }

    // MARK: - Tests

    func test_volumePill_raisesTheCapsule_andADragDimsTheBook() throws {
        try openPlayer()
        let pill = element(AccessibilityID.Player.volume)
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertEqual(pill.label, "Book volume")
        XCTAssertEqual(value(of: AccessibilityID.Player.volume), "100%", "Abbay starts at full volume")

        pill.tap()
        let slider = element(AccessibilityID.Player.volumeSlider)
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "the capsule did not open")
        XCTAssertEqual(value(of: AccessibilityID.Player.volumeSlider), "100%")
        XCTAssertLessThan(slider.frame.maxY, pill.frame.minY, "the capsule sits above the pill")
        XCTAssertEqual(slider.frame.midX, pill.frame.midX, accuracy: 2, "centred over the pill")

        // From near the top of the track to its middle.
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)

        let dimmed = try percent(of: AccessibilityID.Player.volumeSlider)
        // 0–100% fills the bottom two thirds of the track, so the capsule's middle is about 70%.
        XCTAssertTrue((40...95).contains(dimmed), "a drag to the middle dims the book, got \(dimmed)%")
        XCTAssertEqual(try percent(of: AccessibilityID.Player.volume), dimmed, "the pill follows")

        // A tap outside, on the cover, closes the capsule and keeps the level. (Not on the title:
        // its text's centre can sit under the capsule.) The expansion's cover handle stands aside
        // while the capsule is open, as it does for the chapter panel.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(slider.waitForNonExistence(timeout: 5), "a tap outside did not close the capsule")
        XCTAssertEqual(try percent(of: AccessibilityID.Player.volume), dimmed)
    }

    func test_volumePill_secondTap_closesTheCapsule() throws {
        try openPlayer()
        let pill = element(AccessibilityID.Player.volume)
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        let slider = element(AccessibilityID.Player.volumeSlider)

        pill.tap()
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        pill.tap()

        XCTAssertTrue(slider.waitForNonExistence(timeout: 5), "the pill's second tap did not close it")
    }

    /// VoiceOver's swipe up and down on the pill: 10% a step, without opening the capsule.
    func test_volumePill_isAdjustableInPlace() throws {
        try openPlayer()
        let pill = element(AccessibilityID.Player.volume)
        XCTAssertTrue(pill.waitForExistence(timeout: 5))

        try AccessibilityActions.decrement(pill)
        XCTAssertEqual(value(of: AccessibilityID.Player.volume), "90%")
        try AccessibilityActions.decrement(pill)
        XCTAssertEqual(value(of: AccessibilityID.Player.volume), "80%")
        try AccessibilityActions.increment(pill)
        XCTAssertEqual(value(of: AccessibilityID.Player.volume), "90%")
        XCTAssertFalse(element(AccessibilityID.Player.volumeSlider).exists, "adjusting does not open the capsule")
    }

    /// Past 100% (#297): a drag to the top of the capsule boosts the book to 200%.
    func test_dragToTheTop_boostsTo200() throws {
        try openPlayer()
        let pill = element(AccessibilityID.Player.volume)
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        pill.tap()
        let slider = element(AccessibilityID.Player.volumeSlider)
        XCTAssertTrue(slider.waitForExistence(timeout: 5))

        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let top = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.2))
        start.press(forDuration: 0.1, thenDragTo: top)

        XCTAssertEqual(value(of: AccessibilityID.Player.volumeSlider), "200%")
        XCTAssertEqual(value(of: AccessibilityID.Player.volume), "200%")
    }
}
