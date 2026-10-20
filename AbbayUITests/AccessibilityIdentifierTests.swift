//
//  AccessibilityIdentifierTests.swift
//  AbbayUITests
//

import XCTest

/// Proves that every accessibility identifier the feature map promises actually resolves in the
/// running app.
///
/// Identifiers are declarative, so nothing else in the repo can verify them. SwiftUI applies
/// `.accessibilityIdentifier` to **every** accessibility element in a subtree, which means an
/// identifier on a container silently overwrites its children's -- the first version of this
/// suite caught exactly that, with a row container clobbering its title, play button, chapter
/// count and timestamp. Hence the rule the app now follows: identifiers on leaves only.
///
/// State comes from `-seedLibrary` / `-resetLibrary` (see `LaunchArgument`), handled by
/// `UITestSeeder` in DEBUG builds.
final class AccessibilityIdentifierTests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app.terminate()
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func launch(_ arguments: [String]) {
        app.launchArguments = arguments
        app.launch()
    }

    /// Type-agnostic lookup. A driver needs the identifier to resolve; which `XCUIElementType`
    /// SwiftUI happened to emit is an implementation detail not worth hard-coding.
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

    /// Row order comes straight from `LoadAllAudiosUseCase`, which applies no sort, so the
    /// seeded books do not appear in insertion order. Resolve a row by its title instead of
    /// assuming an index.
    private func rowIndex(titled title: String, maxRows: Int = 4) -> Int? {
        for index in 0..<maxRows {
            let candidate = element(AccessibilityID.Element.title(AccessibilityID.Library.row(index)))
            if candidate.exists, candidate.label == title {
                return index
            }
        }
        return nil
    }

    private func openPlayer(forBookTitled title: String) throws -> Int {
        launch([LaunchArgument.seedLibrary])
        assertResolves(AccessibilityID.Library.list)
        let index = try XCTUnwrap(rowIndex(titled: title), "no seeded row titled \"\(title)\"")
        element(AccessibilityID.Element.title(AccessibilityID.Library.row(index))).tap()
        assertResolves(AccessibilityID.Player.transport(AccessibilityID.Transport.play))
        return index
    }

    // MARK: - Library

    func test_emptyLibrary_emptyStateResolves() {
        launch([LaunchArgument.resetLibrary])

        assertResolves(AccessibilityID.Library.empty)
    }

    func test_toolbarIdentifiersResolve() {
        launch([LaunchArgument.resetLibrary])

        assertResolves(AccessibilityID.Library.toolbarSearch)
        assertResolves(AccessibilityID.Library.toolbarImport)
        assertResolves(AccessibilityID.Library.toolbarSettings)
    }

    func test_seededLibrary_listResolves() {
        launch([LaunchArgument.seedLibrary])

        assertResolves(AccessibilityID.Library.list)
    }

    func test_seededLibrary_rowLeafIdentifiersResolve() throws {
        launch([LaunchArgument.seedLibrary])
        assertResolves(AccessibilityID.Library.list)
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Chaptered Book"))
        let row = AccessibilityID.Library.row(index)

        assertResolves(AccessibilityID.Element.artwork(row))
        assertResolves(AccessibilityID.Element.title(row))
        assertResolves(AccessibilityID.Element.chapterCount(row))
        assertResolves(AccessibilityID.Element.timestamp(row))
        assertResolves(AccessibilityID.Element.play(row))
    }

    /// Each row must carry its own identifiers rather than inheriting a container's, or a driver
    /// cannot tell the row apart from the play button inside it.
    func test_rowIdentifiersAreDistinctPerRow() throws {
        launch([LaunchArgument.seedLibrary])
        assertResolves(AccessibilityID.Library.list)

        let chaptered = try XCTUnwrap(rowIndex(titled: "Seeded Chaptered Book"))
        let plain = try XCTUnwrap(rowIndex(titled: "Seeded Plain Book"))

        XCTAssertNotEqual(chaptered, plain, "the two seeded books must occupy different rows")
    }

    // MARK: - Player

    func test_tappingRow_opensPlayer() throws {
        _ = try openPlayer(forBookTitled: "Seeded Chaptered Book")
    }

    func test_player_transportIdentifiersResolve() throws {
        _ = try openPlayer(forBookTitled: "Seeded Chaptered Book")

        for control in [
            AccessibilityID.Transport.back30,
            AccessibilityID.Transport.back15,
            AccessibilityID.Transport.play,
            AccessibilityID.Transport.forward15,
            AccessibilityID.Transport.forward30
        ] {
            assertResolves(AccessibilityID.Player.transport(control))
        }
    }

    func test_player_titleResolves() throws {
        _ = try openPlayer(forBookTitled: "Seeded Chaptered Book")

        assertResolves(AccessibilityID.Player.title)
    }

    func test_player_chapterIdentifiersResolve() throws {
        _ = try openPlayer(forBookTitled: "Seeded Chaptered Book")

        assertResolves(AccessibilityID.Player.chaptersTitle)
        // The seeded chaptered book has three chapters.
        assertResolves(AccessibilityID.Player.chapter(0))
        assertResolves(AccessibilityID.Player.chapter(1))
        assertResolves(AccessibilityID.Player.chapter(2))
    }
}
