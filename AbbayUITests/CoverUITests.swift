//
//  CoverUITests.swift
//  AbbayUITests
//

import XCTest

/// LibriVox covers (`AsyncImageView`) report their load state through `AccessibilityID.Cover`.
/// The stub book's cover is a `/dev/null` file URL, which the host allowlist refuses (failed);
/// with `-stubCovers` it is an archive.org URL answered after 12 s (loading, then loaded), and
/// `-stubCoversOffline` leaves only the disk cache. Load, both caches, shared downloads and the
/// allowlist are unit-tested in `AsyncImageLoaderTests` and `CoverDiskCacheTests`.
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

    private func launch(_ extra: [String] = []) {
        app.launchArguments = [LaunchArgument.seedLibrary, LaunchArgument.stubLibriVox] + extra
        app.launch()
    }

    /// Search tab, then the Popular card. The card's cover starts loading as the tab appears; the
    /// details page then shares that load.
    private func openStubDetails() {
        assertResolves(AccessibilityID.Root.tabSearch)
        element(AccessibilityID.Root.tabSearch).tap()
        assertResolves(AccessibilityID.Search.card(0))
        element(AccessibilityID.Search.card(0)).tap()
        assertResolves(AccessibilityID.Detail.download)
    }

    /// Two frames of the loading cover, half a second apart, compared pixel for pixel.
    private func loadingCoverChangesOverTime() throws -> Bool {
        let cover = element(AccessibilityID.Cover.loading)
        let first = cover.screenshot().pngRepresentation
        Thread.sleep(forTimeInterval: 0.5)
        let second = cover.screenshot().pngRepresentation
        // The frames are only meaningful while the cover was still loading for both.
        try XCTSkipUnless(cover.exists, "the cover finished loading before the second frame")
        return first != second
    }

    // MARK: - Tests

    func test_detailCover_thatFailsToLoad_showsTheFallback() {
        launch()
        openStubDetails()

        assertResolves(AccessibilityID.Cover.failed)
        XCTAssertFalse(element(AccessibilityID.Cover.loading).exists)
    }

    /// `-stubCovers` answers after 12 s, so the details page opens while the card's load is still
    /// running and shows it loading, then loaded.
    func test_detailCover_showsLoading_thenLoaded() {
        launch([LaunchArgument.stubCovers])
        openStubDetails()

        assertResolves(AccessibilityID.Cover.loading)
        assertResolves(AccessibilityID.Cover.loaded)
        XCTAssertFalse(element(AccessibilityID.Cover.loading).exists)
        XCTAssertFalse(element(AccessibilityID.Cover.failed).exists)
    }

    /// The first launch stores the cover on disk; the second can't reach the network, so a loaded
    /// cover there came from disk.
    func test_detailCover_afterARelaunch_isServedFromDisk() {
        launch([LaunchArgument.stubCovers])
        openStubDetails()
        assertResolves(AccessibilityID.Cover.loaded)
        app.terminate()

        launch([LaunchArgument.stubCovers, LaunchArgument.stubCoversOffline])
        openStubDetails()

        assertResolves(AccessibilityID.Cover.loaded, timeout: 5)
        XCTAssertFalse(element(AccessibilityID.Cover.failed).exists)
    }

    /// The placeholder sweeps a light band across the tile...
    func test_loadingCover_shimmers() throws {
        launch([LaunchArgument.stubCovers])
        openStubDetails()
        assertResolves(AccessibilityID.Cover.loading)

        XCTAssertTrue(try loadingCoverChangesOverTime(), "the loading cover should shimmer")
    }

    /// ...and with Reduce Motion it is a still `onyx` tile.
    func test_loadingCover_withReduceMotion_isStatic() throws {
        launch([LaunchArgument.stubCovers, LaunchArgument.forceReduceMotion])
        openStubDetails()
        assertResolves(AccessibilityID.Cover.loading)

        XCTAssertFalse(try loadingCoverChangesOverTime(), "with Reduce Motion the loading cover should not move")
    }
}
