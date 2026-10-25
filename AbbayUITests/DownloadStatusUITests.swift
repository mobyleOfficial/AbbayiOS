//
//  DownloadStatusUITests.swift
//  AbbayUITests
//

import XCTest

/// The download status a LibriVox book shows while it downloads (#148, #171): the progress bar, a
/// failed chapter's retry, the hold hint under the bar on the LibriVox page and the details screen,
/// and the Library ring's label.
///
/// `-stubDownloadStates` makes the stub book 120 MB, so on a metered path Download asks, and the
/// stub download manager publishes a fixed state for it (chapter 0 downloaded, 1 waiting, 2
/// failed). `-stubPathCellular` / `-stubPathHotspot` / `-stubPathLowDataMode` fix the path. The
/// rules themselves are unit-tested (`DownloadStateStoreTests`, `CellularDownloadPolicyTests`).
final class DownloadStatusUITests: XCTestCase {
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

    /// An empty library, English, the given path; opens the stub book from Popular, taps Download
    /// and answers *Wait for Wi-Fi*.
    private func addWaitForWiFiBook(path: String) {
        app.launchArguments = [
            LaunchArgument.stubLibriVox,
            LaunchArgument.resetLibrary,
            LaunchArgument.resetSettings,
            LaunchArgument.stubDownloadStates,
            path,
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        assertResolves(AccessibilityID.Root.tabSearch)
        element(AccessibilityID.Root.tabSearch).tap()
        assertResolves(AccessibilityID.Search.card(0))
        element(AccessibilityID.Search.card(0)).tap()
        assertResolves(AccessibilityID.Detail.download)
        element(AccessibilityID.Detail.download).tap()
        assertResolves(AccessibilityID.Detail.cellularWait)
        element(AccessibilityID.Detail.cellularWait).tap()
        assertResolves(AccessibilityID.Detail.progress)
    }

    private func openPlayerFromLibrary() {
        element(AccessibilityID.Root.tabLibrary).tap()
        let title = element(AccessibilityID.Element.title(AccessibilityID.Library.row(0)))
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        title.tap()
        assertResolves(AccessibilityID.Player.close)
    }

    // MARK: - LibriVox page

    func test_detail_onCellular_showsProgressRetryAndTheCellularHold() {
        addWaitForWiFiBook(path: LaunchArgument.stubPathCellular)

        assertResolves(AccessibilityID.Detail.cellularHold)
        XCTAssertEqual(element(AccessibilityID.Detail.cellularHold).label, "Waiting for Wi-Fi: on cellular")
        assertResolves(AccessibilityID.Detail.chapterRetry(2))
        XCTAssertFalse(element(AccessibilityID.Detail.chapterRetry(1)).exists, "a waiting chapter has no retry")
        XCTAssertFalse(element(AccessibilityID.Detail.lowDataMode).exists)
        XCTAssertFalse(element(AccessibilityID.Detail.hotspotHold).exists)
    }

    func test_detail_onAHotspot_showsTheHotspotHold() {
        addWaitForWiFiBook(path: LaunchArgument.stubPathHotspot)

        assertResolves(AccessibilityID.Detail.hotspotHold)
        XCTAssertEqual(element(AccessibilityID.Detail.hotspotHold).label, "Waiting for Wi-Fi: on a Personal Hotspot")
        XCTAssertFalse(element(AccessibilityID.Detail.cellularHold).exists)
    }

    func test_detail_inLowDataMode_showsTheLowDataModeHold() {
        addWaitForWiFiBook(path: LaunchArgument.stubPathLowDataMode)

        assertResolves(AccessibilityID.Detail.lowDataMode)
        XCTAssertEqual(element(AccessibilityID.Detail.lowDataMode).label, "Waiting: Low Data Mode is on")
    }

    func test_detail_retry_turnsTheFailedChapterBackToWaiting() {
        addWaitForWiFiBook(path: LaunchArgument.stubPathCellular)
        let retry = element(AccessibilityID.Detail.chapterRetry(2))
        XCTAssertTrue(retry.waitForExistence(timeout: 15))

        retry.tap()

        XCTAssertTrue(retry.waitForNonExistence(timeout: 15), "the retried chapter still offers retry")
    }

    /// *Continue* allows cellular for the book, so the path holds nothing and there is no hint.
    func test_detail_continueOnCellular_showsProgressWithoutAHold() {
        app.launchArguments = [
            LaunchArgument.stubLibriVox,
            LaunchArgument.resetLibrary,
            LaunchArgument.resetSettings,
            LaunchArgument.stubDownloadStates,
            LaunchArgument.stubPathCellular,
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        element(AccessibilityID.Root.tabSearch).tap()
        assertResolves(AccessibilityID.Search.card(0))
        element(AccessibilityID.Search.card(0)).tap()
        assertResolves(AccessibilityID.Detail.download)
        element(AccessibilityID.Detail.download).tap()
        assertResolves(AccessibilityID.Detail.cellularContinue)
        element(AccessibilityID.Detail.cellularContinue).tap()

        assertResolves(AccessibilityID.Detail.progress)
        XCTAssertFalse(element(AccessibilityID.Detail.cellularHold).exists)
    }

    // MARK: - Details screen

    func test_player_onCellular_showsTheCellularHold() {
        addWaitForWiFiBook(path: LaunchArgument.stubPathCellular)
        openPlayerFromLibrary()

        assertResolves(AccessibilityID.Player.downloadCellularHold)
    }

    func test_player_showsProgressAndTheHold() {
        addWaitForWiFiBook(path: LaunchArgument.stubPathLowDataMode)
        openPlayerFromLibrary()

        assertResolves(AccessibilityID.Player.downloadProgress)
        assertResolves(AccessibilityID.Player.downloadLowDataMode)
        assertResolves(AccessibilityID.Player.chapterRetry(2))
    }

    func test_player_onAHotspot_showsTheHotspotHold() {
        addWaitForWiFiBook(path: LaunchArgument.stubPathHotspot)
        openPlayerFromLibrary()

        assertResolves(AccessibilityID.Player.downloadHotspotHold)
        XCTAssertFalse(element(AccessibilityID.Player.downloadCellularHold).exists)
    }

    // MARK: - Library ring

    func test_libraryRing_saysWhyTheDownloadWaits_andPausedOnceTapped() {
        addWaitForWiFiBook(path: LaunchArgument.stubPathCellular)
        element(AccessibilityID.Root.tabLibrary).tap()
        let ring = element(AccessibilityID.Element.downloadRing(AccessibilityID.Library.row(0)))
        XCTAssertTrue(ring.waitForExistence(timeout: 15))

        XCTAssertEqual(ring.label, "Downloading, 33%. Waiting for Wi-Fi: on cellular")
        ring.tap()

        let paused = NSPredicate(format: "label == %@", "Paused")
        let expectation = XCTNSPredicateExpectation(predicate: paused, object: ring)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, "ring label: \(ring.label)")
    }
}
