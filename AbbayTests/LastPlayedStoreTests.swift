//
//  LastPlayedStoreTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class LastPlayedStoreTests: XCTestCase {
    private let suiteName = "abbay.tests.LastPlayedStoreTests"

    override func setUpWithError() throws {
        try super.setUpWithError()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        LastPlayedStore.defaults = defaults
    }

    override func tearDownWithError() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        LastPlayedStore.defaults = .standard
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
}
