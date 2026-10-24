//
//  CoverUITests.swift
//  AbbayUITests
//

import XCTest

/// LibriVox covers (`AsyncImageView`) report their load state through `AccessibilityID.Cover`.
/// Only the failure state is reachable: the stub book's cover is a `/dev/null` file URL, and the
/// loading state is too brief to catch. Load, cache and failure are unit-tested in
/// `AsyncImageLoaderTests`.
final class CoverUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Helpers

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

    // MARK: - Tests

    func test_detailCover_thatFailsToLoad_showsTheFallback() {
        app.launchArguments = [LaunchArgument.seedLibrary, LaunchArgument.stubLibriVox]
        app.launch()
        assertResolves(AccessibilityID.Root.tabSearch)
        element(AccessibilityID.Root.tabSearch).tap()
        assertResolves(AccessibilityID.Search.card(0))
        element(AccessibilityID.Search.card(0)).tap()
        assertResolves(AccessibilityID.Detail.download)

        assertResolves(AccessibilityID.Cover.failed)
        XCTAssertFalse(element(AccessibilityID.Cover.loading).exists)
    }
}
