//
//  LaunchStateFlagTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class LaunchStateFlagTests: XCTestCase {
    private var testSuite: UserDefaults?
    private var suiteName: String?
    private var originalDefaults: UserDefaults?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let name = "test.launch-state-flag.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        suite.removePersistentDomain(forName: name)
        suiteName = name
        testSuite = suite
        originalDefaults = LaunchStateFlag.defaults
        LaunchStateFlag.defaults = suite
    }

    override func tearDownWithError() throws {
        if let name = suiteName, let suite = testSuite {
            suite.removePersistentDomain(forName: name)
        }
        if let original = originalDefaults {
            LaunchStateFlag.defaults = original
        }
        try super.tearDownWithError()
    }

    func test_isUnavailable_defaultsFalse() {
        XCTAssertFalse(LaunchStateFlag.isUnavailable())
    }

    func test_markUnavailable_thenIsUnavailable_returnsTrue() {
        LaunchStateFlag.markUnavailable()
        XCTAssertTrue(LaunchStateFlag.isUnavailable())
    }

    func test_clear_resetsToFalse() {
        LaunchStateFlag.markUnavailable()
        LaunchStateFlag.clear()
        XCTAssertFalse(LaunchStateFlag.isUnavailable())
    }
}
