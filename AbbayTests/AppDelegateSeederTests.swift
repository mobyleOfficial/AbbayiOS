//
//  AppDelegateSeederTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class AppDelegateSeederTests: XCTestCase {
    private func makeSuites() -> (InMemoryKeyValueStore, InMemoryKeyValueStore) {
        (InMemoryKeyValueStore(), InMemoryKeyValueStore())
    }

    func test_seed_lastPlayedInStandardOnly_copiesToAppGroup() {
        let (appGroup, standard) = makeSuites()
        standard.set("file:///old", forKey: LastPlayedStore.key)

        AppDelegateSeeder(appGroup: appGroup, standard: standard).seedIfNeeded()

        XCTAssertEqual(appGroup.object(forKey: LastPlayedStore.key) as? String, "file:///old")
    }

    func test_seed_lastPlayedInAppGroupAlready_doesNotOverwrite() {
        let (appGroup, standard) = makeSuites()
        appGroup.set("file:///existing", forKey: LastPlayedStore.key)
        standard.set("file:///stale", forKey: LastPlayedStore.key)

        AppDelegateSeeder(appGroup: appGroup, standard: standard).seedIfNeeded()

        XCTAssertEqual(appGroup.object(forKey: LastPlayedStore.key) as? String, "file:///existing")
    }

    /// #153: the launch writes the library snapshot itself (`AppDelegateOrderingTests`), so the
    /// seeder leaves it alone, even when there is none yet.
    func test_seed_noSnapshot_leavesTheSnapshotToTheLaunchWrite() {
        let (appGroup, standard) = makeSuites()

        AppDelegateSeeder(appGroup: appGroup, standard: standard).seedIfNeeded()

        XCTAssertNil(appGroup.object(forKey: LibrarySnapshotWriter.key))
    }
}
