//
//  LastPlayedStoreTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class LastPlayedStoreTests: XCTestCase {
    private var suiteName: String = ""
    private var fallbackSuiteName: String = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Unique suite per test instance so parallel test runs don't collide.
        suiteName = "abbay.tests.LastPlayedStoreTests.\(UUID().uuidString)"
        fallbackSuiteName = "abbay.tests.LastPlayedStoreTests.fallback.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let fallback = try XCTUnwrap(UserDefaults(suiteName: fallbackSuiteName))
        fallback.removePersistentDomain(forName: fallbackSuiteName)
        LastPlayedStore.defaults = defaults
        // Inject empty fallback so a value leaked into `.standard` by an
        // earlier test (or this process's first run) cannot bleed through.
        LastPlayedStore.standardFallback = fallback
    }

    override func tearDownWithError() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let fallback = try XCTUnwrap(UserDefaults(suiteName: fallbackSuiteName))
        fallback.removePersistentDomain(forName: fallbackSuiteName)
        LastPlayedStore.defaults = AppGroup.defaults
        LastPlayedStore.standardFallback = .standard
        try super.tearDownWithError()
    }

    func test_lastPlayedURL_isNil_byDefault() {
        XCTAssertNil(LastPlayedStore.lastPlayedURL())
    }

    func test_save_thenRead_roundTripsURL() {
        let url = URL(fileURLWithPath: "/tmp/book.m4b")
        LastPlayedStore.save(url: url)
        XCTAssertEqual(LastPlayedStore.lastPlayedURL(), url)
    }

    func test_save_nil_clearsExistingValue() {
        let url = URL(fileURLWithPath: "/tmp/book.m4b")
        LastPlayedStore.save(url: url)
        LastPlayedStore.save(url: nil)
        XCTAssertNil(LastPlayedStore.lastPlayedURL())
    }

    func test_save_nil_alsoClearsStandardFallback_preventsStuckStateLoop() throws {
        // Phase-1 install path: value lives only in `.standard` (here: injected fallback).
        // Caller invokes the stuck-state clear via `save(url: nil)` after detecting a
        // dead pointer. Read must NOT resurface the phase-1 value via the fallback chain.
        LastPlayedStore.standardFallback.set("file:///dead", forKey: LastPlayedStore.key)
        XCTAssertEqual(LastPlayedStore.lastPlayedURL()?.absoluteString, "file:///dead")

        LastPlayedStore.save(url: nil)

        XCTAssertNil(LastPlayedStore.lastPlayedURL())
        XCTAssertNil(LastPlayedStore.standardFallback.string(forKey: LastPlayedStore.key))
    }

    func test_migration_standardToAppGroup_seedThenWrite_zeroLoss() throws {
        let standardSuiteName = "test.standard.\(UUID().uuidString)"
        let appGroupSuiteName = "test.appgroup.\(UUID().uuidString)"
        let standard = try XCTUnwrap(UserDefaults(suiteName: standardSuiteName))
        let appGroup = try XCTUnwrap(UserDefaults(suiteName: appGroupSuiteName))
        defer {
            standard.removePersistentDomain(forName: standardSuiteName)
            appGroup.removePersistentDomain(forName: appGroupSuiteName)
            LastPlayedStore.defaults = AppGroup.defaults
            LastPlayedStore.standardFallback = .standard
        }

        standard.set("file:///old/url", forKey: LastPlayedStore.key)
        LastPlayedStore.defaults = appGroup
        LastPlayedStore.standardFallback = standard

        // Pre-migration read: AppGroup empty AND standard has → returns .standard value
        XCTAssertEqual(LastPlayedStore.lastPlayedURL()?.absoluteString, "file:///old/url")
        XCTAssertNil(appGroup.string(forKey: LastPlayedStore.key))

        // Write triggers seed-then-write
        let newURL = try XCTUnwrap(URL(string: "file:///new/url"))
        LastPlayedStore.save(url: newURL)
        XCTAssertEqual(appGroup.string(forKey: LastPlayedStore.key), "file:///new/url")
        XCTAssertEqual(LastPlayedStore.lastPlayedURL()?.absoluteString, "file:///new/url")
    }

    func test_read_preservesTestInjectionSeam() throws {
        let suiteName = "test.seam.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let original = LastPlayedStore.defaults
        LastPlayedStore.defaults = suite
        defer {
            suite.removePersistentDomain(forName: suiteName)
            LastPlayedStore.defaults = original
        }
        suite.set("file:///x", forKey: LastPlayedStore.key)
        XCTAssertEqual(LastPlayedStore.lastPlayedURL()?.absoluteString, "file:///x")
    }
}
