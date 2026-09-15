//
//  AppGroupTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class AppGroupTests: XCTestCase {
    func test_suiteName_matchesPhase2Spec() {
        XCTAssertEqual(AppGroup.suiteName, "group.com.edyuto.abbay")
    }

    func test_defaults_returnsNonNilUserDefaults() {
        XCTAssertNotNil(AppGroup.defaults)
    }
}
