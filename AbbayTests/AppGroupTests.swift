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

    func test_store_isTheAppGroupSuite() {
        XCTAssertTrue(AppGroup.store is UserDefaults)
    }

    /// A name `UserDefaults` refuses no longer traps: the store falls back to one that lives for
    /// the process, and still works.
    func test_makeStore_withAReservedName_fallsBackToAProcessLocalStore() {
        let store = AppGroup.makeStore(suiteName: "NSGlobalDomain")

        XCTAssertTrue(store is InMemoryKeyValueStore)
        store.set("value", forKey: "key")
        XCTAssertEqual(store.object(forKey: "key") as? String, "value")
    }
}
