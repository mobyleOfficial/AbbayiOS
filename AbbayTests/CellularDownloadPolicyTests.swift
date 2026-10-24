//
//  CellularDownloadPolicyTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class CellularDownloadPolicyTests: XCTestCase {
    func testAtThresholdOnCellularProceedsAllowingCellular() {
        let decision = CellularDownloadPolicy.decide(totalBytes: 99_000_000, isMetered: true)
        XCTAssertEqual(decision, .proceed(allowsCellular: true))
    }

    func testAboveThresholdOnCellularAsksUser() {
        let decision = CellularDownloadPolicy.decide(totalBytes: 99_000_001, isMetered: true)
        XCTAssertEqual(decision, .askUser)
    }

    func testAboveThresholdOnWifiProceedsWithoutCellular() {
        let decision = CellularDownloadPolicy.decide(totalBytes: 99_000_001, isMetered: false)
        XCTAssertEqual(decision, .proceed(allowsCellular: false))
    }

    func testZeroBytesOnCellularProceedsAllowingCellular() {
        let decision = CellularDownloadPolicy.decide(totalBytes: 0, isMetered: true)
        XCTAssertEqual(decision, .proceed(allowsCellular: true))
    }

    // MARK: - The Settings preference (large books only)

    func testAskIsTheDefault_andKeepsThePrompt() {
        let decision = CellularDownloadPolicy.decide(totalBytes: 99_000_001, isMetered: true, preference: .ask)
        XCTAssertEqual(decision, .askUser)
    }

    func testAlways_startsALargeBookOnCellularWithoutAsking() {
        XCTAssertEqual(
            CellularDownloadPolicy.decide(totalBytes: 99_000_001, isMetered: true, preference: .always),
            .proceed(allowsCellular: true)
        )
        XCTAssertEqual(
            CellularDownloadPolicy.decide(totalBytes: 99_000_001, isMetered: false, preference: .always),
            .proceed(allowsCellular: true),
            "started on Wi-Fi, it carries on if the phone moves to cellular"
        )
    }

    func testWifiOnly_startsALargeBookWithoutCellularWithoutAsking() {
        XCTAssertEqual(
            CellularDownloadPolicy.decide(totalBytes: 99_000_001, isMetered: true, preference: .wifiOnly),
            .proceed(allowsCellular: false)
        )
        XCTAssertEqual(
            CellularDownloadPolicy.decide(totalBytes: 99_000_001, isMetered: false, preference: .wifiOnly),
            .proceed(allowsCellular: false)
        )
    }

    /// The preference is about large downloads: a small book downloads on any network whatever it says.
    func testSmallBooks_ignoreThePreference() {
        for preference in CellularDownloadPreference.allCases {
            XCTAssertEqual(
                CellularDownloadPolicy.decide(totalBytes: 10_000_000, isMetered: true, preference: preference),
                .proceed(allowsCellular: true),
                "\(preference)"
            )
        }
    }
}

/// What `NetworkPathMonitor` reports for a path, without a real `NWPath`.
final class NetworkPathSnapshotTests: XCTestCase {
    func testCellularOnlyIsMetered() {
        XCTAssertTrue(path(cellular: true, wifi: false, expensive: true).isMetered)
    }

    /// Personal Hotspot: Wi-Fi, but paid for by another phone's cellular plan.
    func testExpensiveWiFiIsMetered() {
        XCTAssertTrue(path(wifi: true, expensive: true).isMetered)
    }

    /// Low Data Mode.
    func testConstrainedWiFiIsMetered() {
        XCTAssertTrue(path(wifi: true, constrained: true).isMetered)
    }

    func testPlainWiFiIsNotMetered() {
        XCTAssertFalse(path(wifi: true).isMetered)
    }

    func testWiFiWithCellularFallbackIsNotMetered() {
        XCTAssertFalse(path(cellular: true, wifi: true).isMetered)
    }

    func testUnknownPathIsOnlineAndNotMetered() {
        XCTAssertTrue(NetworkPathSnapshot.unknown.isSatisfied)
        XCTAssertFalse(NetworkPathSnapshot.unknown.isMetered)
        XCTAssertFalse(NetworkPathSnapshot.unknown.isLowDataModeWiFi)
    }

    /// The one hold the app explains (#148): Wi-Fi in Low Data Mode. On cellular or a hotspot a
    /// Wait-for-Wi-Fi book waits as asked, Low Data Mode or not.
    func testLowDataModeWiFi_onlyOnConstrainedWiFiThatIsOtherwiseUnmetered() {
        XCTAssertTrue(path(wifi: true, constrained: true).isLowDataModeWiFi)
        XCTAssertTrue(path(cellular: true, wifi: true, constrained: true).isLowDataModeWiFi)
        XCTAssertFalse(path(wifi: true).isLowDataModeWiFi)
        XCTAssertFalse(path(wifi: true, expensive: true, constrained: true).isLowDataModeWiFi, "Hotspot")
        XCTAssertFalse(path(cellular: true, expensive: true, constrained: true).isLowDataModeWiFi, "Cellular")
        let offline = NetworkPathSnapshot(
            isSatisfied: false, usesCellular: false, usesWiFi: true, isExpensive: false, isConstrained: true
        )
        XCTAssertFalse(offline.isLowDataModeWiFi)
    }

    private func path(
        cellular: Bool = false,
        wifi: Bool = false,
        expensive: Bool = false,
        constrained: Bool = false
    ) -> NetworkPathSnapshot {
        NetworkPathSnapshot(
            isSatisfied: true,
            usesCellular: cellular,
            usesWiFi: wifi,
            isExpensive: expensive,
            isConstrained: constrained
        )
    }
}
