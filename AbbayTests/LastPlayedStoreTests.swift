//
//  LastPlayedStoreTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class LastPlayedStoreTests: XCTestCase {
    /// Fresh per test (XCTest builds one instance per test), so nothing leaks between them.
    private let appGroup = InMemoryKeyValueStore()
    /// Stands in for `.standard`, where phase-1 installs kept the value.
    private let standard = InMemoryKeyValueStore()
    private var store: LastPlayedStore { LastPlayedStore(store: appGroup, legacyStore: standard) }

    func test_lastPlayedURL_isNil_byDefault() {
        XCTAssertNil(store.lastPlayedURL())
    }

    func test_save_thenRead_roundTripsURL() {
        let url = URL(fileURLWithPath: "/tmp/book.m4b")
        store.save(url: url)
        XCTAssertEqual(store.lastPlayedURL(), url)
    }

    func test_save_nil_clearsExistingValue() {
        let url = URL(fileURLWithPath: "/tmp/book.m4b")
        store.save(url: url)
        store.save(url: nil)
        XCTAssertNil(store.lastPlayedURL())
    }

    func test_save_nil_alsoClearsStandardFallback_preventsStuckStateLoop() throws {
        // Phase-1 install path: value lives only in `.standard` (here: the legacy store).
        // Caller invokes the stuck-state clear via `save(url: nil)` after detecting a
        // dead pointer. Read must NOT resurface the phase-1 value via the fallback chain.
        standard.set("file:///dead", forKey: LastPlayedStore.key)
        XCTAssertEqual(store.lastPlayedURL()?.absoluteString, "file:///dead")

        store.save(url: nil)

        XCTAssertNil(store.lastPlayedURL())
        XCTAssertNil(standard.object(forKey: LastPlayedStore.key))
    }

    func test_migration_standardToAppGroup_seedThenWrite_zeroLoss() throws {
        standard.set("file:///old/url", forKey: LastPlayedStore.key)

        // Pre-migration read: AppGroup empty AND standard has → returns .standard value
        XCTAssertEqual(store.lastPlayedURL()?.absoluteString, "file:///old/url")
        XCTAssertNil(appGroup.object(forKey: LastPlayedStore.key))

        // Write triggers seed-then-write
        let newURL = try XCTUnwrap(URL(string: "file:///new/url"))
        store.save(url: newURL)
        XCTAssertEqual(appGroup.object(forKey: LastPlayedStore.key) as? String, "file:///new/url")
        XCTAssertEqual(store.lastPlayedURL()?.absoluteString, "file:///new/url")
    }

    func test_read_prefersTheAppGroupOverStandard() {
        appGroup.set("file:///x", forKey: LastPlayedStore.key)
        standard.set("file:///stale", forKey: LastPlayedStore.key)
        XCTAssertEqual(store.lastPlayedURL()?.absoluteString, "file:///x")
    }

    /// On-disk compatibility: an install upgraded from the `UserDefaults`-only version reads the
    /// pointer it already has, under the same key, and writes one the old code could read.
    func test_readsAndWritesTheSameValueAsUserDefaults() throws {
        let name = "test.last-played.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { suite.removePersistentDomain(forName: name) }
        let store = LastPlayedStore(store: suite, legacyStore: standard)

        suite.set("file:///existing", forKey: "abbay.lastPlayedAudioURL")
        XCTAssertEqual(store.lastPlayedURL()?.absoluteString, "file:///existing")

        store.save(url: try XCTUnwrap(URL(string: "file:///next")))
        XCTAssertEqual(suite.string(forKey: "abbay.lastPlayedAudioURL"), "file:///next")
    }
}
