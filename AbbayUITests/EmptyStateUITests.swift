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
        XCTAssertTrue(element(AccessibilityID.Player.chaptersTitle).waitForExistence(timeout: 10))
    }

    // MARK: - Tests

    func test_playerChapterList_forABookWithNoChapters_saysSo() throws {
        try openPlayer(for: "Seeded Plain Book")

        let empty = element(AccessibilityID.Player.chaptersEmpty)
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "no empty state in the chapter list")
        XCTAssertTrue(empty.label.contains("No chapters"), "unexpected: \"\(empty.label)\"")
        XCTAssertFalse(element(AccessibilityID.Player.chapter(0)).exists)
    }

    func test_playerChapterList_forABookWithChapters_showsRowsAndNoEmptyState() throws {
        try openPlayer(for: "Seeded Chaptered Book")

        XCTAssertTrue(element(AccessibilityID.Player.chapter(0)).waitForExistence(timeout: 5))
        XCTAssertFalse(element(AccessibilityID.Player.chaptersEmpty).exists)
    }
}
