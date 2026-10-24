//
//  AppDelegateSeederTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class AppDelegateSeederTests: XCTestCase {
    private func makeSuites() throws -> (InMemoryKeyValueStore, InMemoryKeyValueStore) {
        (InMemoryKeyValueStore(), InMemoryKeyValueStore())
    }

    func test_seed_lastPlayedInStandardOnly_copiesToAppGroup() throws {
        let (appGroup, standard) = try makeSuites()
        standard.set("file:///old", forKey: LastPlayedStore.key)
        appGroup.set(Data(), forKey: LibrarySnapshotWriter.key)  // snapshot present → skip refresh
        let mockWriter = MockLibrarySnapshotWriter()

        AppDelegateSeeder(appGroup: appGroup, standard: standard, snapshotWriter: mockWriter)
            .seedIfNeeded()

        XCTAssertEqual(appGroup.object(forKey: LastPlayedStore.key) as? String, "file:///old")
        XCTAssertEqual(mockWriter.refreshCallCount, 0)
    }

    func test_seed_emptySnapshot_callsRefresh() throws {
        let (appGroup, standard) = try makeSuites()
        let mockWriter = MockLibrarySnapshotWriter()

        AppDelegateSeeder(appGroup: appGroup, standard: standard, snapshotWriter: mockWriter)
            .seedIfNeeded()

        XCTAssertEqual(mockWriter.refreshCallCount, 1)
    }

    func test_seed_populatedSnapshot_skipsRefresh() throws {
        let (appGroup, standard) = try makeSuites()
        appGroup.set(Data([1, 2]), forKey: LibrarySnapshotWriter.key)
        let mockWriter = MockLibrarySnapshotWriter()

        AppDelegateSeeder(appGroup: appGroup, standard: standard, snapshotWriter: mockWriter)
            .seedIfNeeded()

        XCTAssertEqual(mockWriter.refreshCallCount, 0)
    }

    func test_seed_lastPlayedInAppGroupAlready_doesNotOverwrite() throws {
        let (appGroup, standard) = try makeSuites()
        appGroup.set("file:///existing", forKey: LastPlayedStore.key)
        standard.set("file:///stale", forKey: LastPlayedStore.key)
        appGroup.set(Data(), forKey: LibrarySnapshotWriter.key)

        AppDelegateSeeder(
            appGroup: appGroup,
            standard: standard,
            snapshotWriter: MockLibrarySnapshotWriter()
        ).seedIfNeeded()

        XCTAssertEqual(appGroup.object(forKey: LastPlayedStore.key) as? String, "file:///existing")
    }
}
