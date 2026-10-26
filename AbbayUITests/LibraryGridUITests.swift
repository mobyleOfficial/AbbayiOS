//
//  LibraryGridUITests.swift
//  AbbayUITests
//

import XCTest

/// The library grid (#166 G3): the cells' status lines, the Continue card (`library.continue*`)
/// and the cells' context menu (`library.row.N.play` / `.delete`).
final class LibraryGridUITests: XCTestCase {
    private var app = XCUIApplication()
    private let libraryPrompt = "Search your library"

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Helpers

    private func launch(_ arguments: [String]) {
        app.launchArguments = arguments
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertResolves(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            element(identifier).waitForExistence(timeout: 15),
            "no element resolves identifier \"\(identifier)\"",
            file: file,
            line: line
        )
    }

    private func searchField(prompt: String) -> XCUIElement {
        app.searchFields.matching(NSPredicate(format: "placeholderValue == %@", prompt)).firstMatch
    }

    /// Cell order isn't insertion order (`LoadAllAudiosUseCase` doesn't sort): find it by title.
    private func rowIndex(titled title: String, maxRows: Int = 6) -> Int? {
        for index in 0..<maxRows {
            let candidate = element(AccessibilityID.Element.title(AccessibilityID.Library.row(index)))
            if candidate.exists, candidate.label == title {
                return index
            }
        }
        return nil
    }

    // MARK: - Status line

    /// A cell's status line before a book is started and once it is listened to the end.
    func test_seededCells_showNewAndFinished() throws {
        launch([LaunchArgument.seedLibrary, LaunchArgument.seedTimeLeftEdges])
        assertResolves(AccessibilityID.Library.list)
        let plain = try XCTUnwrap(rowIndex(titled: "Seeded Plain Book"))
        let finished = try XCTUnwrap(rowIndex(titled: "Seeded Finished Book"))

        XCTAssertEqual(element(AccessibilityID.Element.detail(AccessibilityID.Library.row(plain))).label, "New")
        let finishedDetail = element(AccessibilityID.Element.detail(AccessibilityID.Library.row(finished)))
        XCTAssertEqual(finishedDetail.label, "Finished ✓")
    }

    // MARK: - Continue card

    func test_continueCard_showsTheLastPlayedBook_andResumes() {
        launch([LaunchArgument.seedLibrary, LaunchArgument.seedLastPlayed])
        assertResolves(AccessibilityID.Library.continueTitle)
        XCTAssertEqual(element(AccessibilityID.Library.continueTitle).label, "Seeded Chaptered Book")
        let detail = element(AccessibilityID.Library.continueDetail)
        XCTAssertTrue(detail.label.hasPrefix("Chapter 2"), "card detail: \"\(detail.label)\"")
        let resume = element(AccessibilityID.Library.continueResume)
        XCTAssertEqual(resume.label, "Resume")

        resume.tap()

        assertResolves(AccessibilityID.MiniPlayer.bar)
        let pause = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Pause"), object: resume)
        XCTAssertEqual(XCTWaiter.wait(for: [pause], timeout: 10), .completed, "resume reads \"\(resume.label)\"")
    }

    func test_continueCard_tapOpensThePlayer() {
        launch([LaunchArgument.seedLibrary, LaunchArgument.seedLastPlayed])
        assertResolves(AccessibilityID.Library.continueTitle)

        element(AccessibilityID.Library.continueTitle).tap()

        assertResolves(AccessibilityID.Player.close)
    }

    /// Seeding clears last played, so a library nobody has played from has no card.
    func test_continueCard_absentWithoutALastPlayedBook() {
        launch([LaunchArgument.seedLibrary])
        assertResolves(AccessibilityID.Library.list)

        XCTAssertFalse(element(AccessibilityID.Library.continueTitle).waitForExistence(timeout: 3))
    }

    func test_continueCard_hiddenWhileSearching() {
        launch([LaunchArgument.seedLibrary, LaunchArgument.seedLastPlayed])
        assertResolves(AccessibilityID.Library.continueTitle)
        let field = searchField(prompt: libraryPrompt)

        field.tap()
        field.typeText("Seeded")

        XCTAssertTrue(element(AccessibilityID.Library.continueTitle).waitForNonExistence(timeout: 5))
        assertResolves(AccessibilityID.Element.title(AccessibilityID.Library.row(0)))
    }

    // MARK: - Context menu

    /// Delete moved from a trailing swipe to the cell's context menu; the last one leaves the
    /// empty state.
    func test_contextMenuDelete_removesTheBook() throws {
        launch([LaunchArgument.seedLibrary])
        assertResolves(AccessibilityID.Library.list)
        let plain = try XCTUnwrap(rowIndex(titled: "Seeded Plain Book"))

        LibraryGridActions.delete(in: app, cell: plain)

        XCTAssertTrue(app.staticTexts["Seeded Plain Book"].waitForNonExistence(timeout: 10))
        LibraryGridActions.delete(in: app, cell: 0)
        assertResolves(AccessibilityID.Library.empty)
    }
}
