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
