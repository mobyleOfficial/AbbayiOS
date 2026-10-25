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

    /// Wi-Fi in Low Data Mode (#148). On cellular or a hotspot the hold is that instead, Low Data
    /// Mode or not.
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

    /// Every path that holds a Wait-for-Wi-Fi book names why (#171); cellular first, then a
    /// hotspot, then Low Data Mode.
    func testHold_namesWhatHoldsAWaitForWiFiBook() {
        XCTAssertEqual(path(cellular: true).hold, .cellular)
        XCTAssertEqual(path(cellular: true, expensive: true).hold, .cellular)
        XCTAssertEqual(path(cellular: true, expensive: true, constrained: true).hold, .cellular)
        XCTAssertEqual(path(wifi: true, expensive: true).hold, .personalHotspot)
        XCTAssertEqual(path(wifi: true, expensive: true, constrained: true).hold, .personalHotspot)
        XCTAssertEqual(path(wifi: true, constrained: true).hold, .lowDataMode)
        XCTAssertEqual(path(cellular: true, wifi: true, constrained: true).hold, .lowDataMode)
    }

    func testHold_isNilOnUnmeteredWiFi_offline_andBeforeTheFirstUpdate() {
        XCTAssertNil(path(wifi: true).hold)
        XCTAssertNil(path(cellular: true, wifi: true).hold)
        XCTAssertNil(NetworkPathSnapshot.unknown.hold)
        let offlineCellular = NetworkPathSnapshot(
            isSatisfied: false, usesCellular: true, usesWiFi: false, isExpensive: true, isConstrained: false
        )
        XCTAssertNil(offlineCellular.hold)
    }

    /// A path holds a Wait-for-Wi-Fi book exactly when it is metered and online, so a held book
    /// always has a reason to show.
    func testHold_isSetExactlyOnMeteredOnlinePaths() {
        for bits in 0..<16 {
            let snapshot = path(
                cellular: bits & 1 != 0, wifi: bits & 2 != 0, expensive: bits & 4 != 0, constrained: bits & 8 != 0
            )
            XCTAssertEqual(snapshot.hold != nil, snapshot.isMetered, "\(snapshot)")
        }
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
