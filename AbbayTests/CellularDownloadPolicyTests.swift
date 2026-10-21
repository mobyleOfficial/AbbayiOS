//
//  CellularDownloadPolicyTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class CellularDownloadPolicyTests: XCTestCase {
    func testAtThresholdOnCellularProceedsAllowingCellular() {
        let decision = CellularDownloadPolicy.decide(totalBytes: 99_000_000, isCellular: true)
        XCTAssertEqual(decision, .proceed(allowsCellular: true))
    }

    func testAboveThresholdOnCellularAsksUser() {
        let decision = CellularDownloadPolicy.decide(totalBytes: 99_000_001, isCellular: true)
        XCTAssertEqual(decision, .askUser)
    }

    func testAboveThresholdOnWifiProceedsWithoutCellular() {
        let decision = CellularDownloadPolicy.decide(totalBytes: 99_000_001, isCellular: false)
        XCTAssertEqual(decision, .proceed(allowsCellular: false))
    }

    func testZeroBytesOnCellularProceedsAllowingCellular() {
        let decision = CellularDownloadPolicy.decide(totalBytes: 0, isCellular: true)
        XCTAssertEqual(decision, .proceed(allowsCellular: true))
    }
}
