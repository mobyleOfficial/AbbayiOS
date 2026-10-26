//
//  GlassTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// `View+Glass.swift` is the redesign's only OS check (#166 G6): real glass from iOS 26, the
/// plain system look before.
final class GlassTests: XCTestCase {
    func test_isAvailable_matchesTheRunningOS() {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        XCTAssertEqual(AbbayGlass.isAvailable, major >= 26)
    }
}
