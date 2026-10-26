//
//  EmptyStateUITests.swift
//  AbbayUITests
//

import XCTest

/// Empty states (#115): a list with nothing in it says so, rather than showing a blank card.
/// "Seeded Plain Book" has no chapter markers; "Seeded Chaptered Book" has three.
final class EmptyStateUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [LaunchArgument.seedLibrary]
        app.launch()
    }

    // MARK: - Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Row order isn't insertion order (`LoadAllAudiosUseCase` doesn't sort): find it by title.
    private func rowTitle(_ title: String, maxRows: Int = 4) -> XCUIElement? {
        for index in 0..<maxRows {
            let candidate = element(AccessibilityID.Element.title(AccessibilityID.Library.row(index)))
            if candidate.exists, candidate.label == title {
                return candidate
            }
        }
        return nil
    }

    private func openPlayer(for title: String) throws {
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 15))
        try XCTUnwrap(rowTitle(title), "no seeded row titled \"\(title)\"").tap()
        XCTAssertTrue(element(AccessibilityID.Player.speed).waitForExistence(timeout: 10))
    }

    // MARK: - Tests

    /// #166 G1: a book with no chapters has no Chapters pill (and so no "No chapters" message on
    /// the player); the speed pill is still there.
    func test_player_forABookWithNoChapters_hasNoChaptersPill() throws {
        try openPlayer(for: "Seeded Plain Book")

        XCTAssertTrue(element(AccessibilityID.Player.speed).exists)
        XCTAssertFalse(element(AccessibilityID.Player.chapters).exists, "a book without chapters shows the pill")
        XCTAssertFalse(element(AccessibilityID.Player.chapter(0)).exists)
    }

    func test_player_forABookWithChapters_opensTheirPanel() throws {
        try openPlayer(for: "Seeded Chaptered Book")

        let pill = element(AccessibilityID.Player.chapters)
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "no Chapters pill")
        pill.tap()
        XCTAssertTrue(element(AccessibilityID.Player.chapter(0)).waitForExistence(timeout: 5))
    }
}
