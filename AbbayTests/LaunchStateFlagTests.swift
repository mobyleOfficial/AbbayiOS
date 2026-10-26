//
//  LaunchStateFlagTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class LaunchStateFlagTests: XCTestCase {
    private let store = InMemoryKeyValueStore()
    private var flag: LaunchStateFlag { LaunchStateFlag(store: store) }

    func test_isUnavailable_defaultsFalse() {
        XCTAssertFalse(flag.isUnavailable())
    }

    func test_markUnavailable_thenIsUnavailable_returnsTrue() {
        flag.markUnavailable()
        XCTAssertTrue(flag.isUnavailable())
    }

    func test_clear_resetsToFalse() {
        flag.markUnavailable()
        flag.clear()
        XCTAssertFalse(flag.isUnavailable())
    }

    /// The flag the extension reads is the value the app wrote: same key, and a `Bool` both ways,
    /// so installs that set it before the store was injected still read it.
    func test_readsAndWritesTheSameValueAsUserDefaults() throws {
        let name = "test.launch-state-flag.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { suite.removePersistentDomain(forName: name) }

        suite.set(true, forKey: "abbay.audioSessionUnavailable")
        XCTAssertTrue(LaunchStateFlag(store: suite).isUnavailable())

        LaunchStateFlag(store: suite).clear()
        LaunchStateFlag(store: suite).markUnavailable()
        XCTAssertTrue(suite.bool(forKey: "abbay.audioSessionUnavailable"))
    }
}
