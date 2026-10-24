//
//  DebugOverridesTests.swift
//  AbbayTests
//

#if DEBUG
@testable import Abbay
import XCTest

/// `-forceReduceMotion` is how the UI tests get Reduce Motion: `nil` must mean "follow the
/// system", so a normal launch never overrides the user's setting.
final class DebugOverridesTests: XCTestCase {
    func test_reduceMotion_withoutTheArgument_followsTheSystem() {
        XCTAssertNil(DebugOverrides.reduceMotion(arguments: ["/path/to/Abbay", LaunchArgument.seedLibrary]))
    }

    func test_reduceMotion_withTheArgument_isForcedOn() {
        XCTAssertEqual(DebugOverrides.reduceMotion(arguments: [LaunchArgument.forceReduceMotion]), true)
    }
}
#endif
