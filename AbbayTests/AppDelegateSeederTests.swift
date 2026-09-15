//
//  AppDelegateSeederTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class AppDelegateSeederTests: XCTestCase {
    private var createdSuites: [(name: String, suite: UserDefaults)] = []

    override func tearDownWithError() throws {
        for entry in createdSuites {
            entry.suite.removePersistentDomain(forName: entry.name)
        }
        createdSuites.removeAll()
        try super.tearDownWithError()
    }

    private func makeSuites() throws -> (UserDefaults, UserDefaults) {
        let appGroupName = "test.appgroup.\(UUID().uuidString)"
        let standardName = "test.standard.\(UUID().uuidString)"
        let appGroup = try XCTUnwrap(UserDefaults(suiteName: appGroupName))
        let standard = try XCTUnwrap(UserDefaults(suiteName: standardName))
        createdSuites.append((appGroupName, appGroup))
        createdSuites.append((standardName, standard))
        return (appGroup, standard)
    }

    func test_seed_lastPlayedInStandardOnly_copiesToAppGroup() throws {
        let (appGroup, standard) = try makeSuites()
        standard.set("file:///old", forKey: LastPlayedStore.key)
        appGroup.set(Data(), forKey: LibrarySnapshotWriter.key)  // snapshot present → skip refresh
        let mockWriter = MockLibrarySnapshotWriter()

        AppDelegateSeeder(lastPlayedSuite: appGroup, standard: standard, snapshotWriter: mockWriter)
            .seedIfNeeded()

        XCTAssertEqual(appGroup.string(forKey: LastPlayedStore.key), "file:///old")
        XCTAssertEqual(mockWriter.refreshCallCount, 0)
    }

    func test_seed_emptySnapshot_callsRefresh() throws {
        let (appGroup, standard) = try makeSuites()
        let mockWriter = MockLibrarySnapshotWriter()

        AppDelegateSeeder(lastPlayedSuite: appGroup, standard: standard, snapshotWriter: mockWriter)
            .seedIfNeeded()

        XCTAssertEqual(mockWriter.refreshCallCount, 1)
    }

    func test_seed_populatedSnapshot_skipsRefresh() throws {
        let (appGroup, standard) = try makeSuites()
        appGroup.set(Data([1, 2]), forKey: LibrarySnapshotWriter.key)
        let mockWriter = MockLibrarySnapshotWriter()

        AppDelegateSeeder(lastPlayedSuite: appGroup, standard: standard, snapshotWriter: mockWriter)
            .seedIfNeeded()

        XCTAssertEqual(mockWriter.refreshCallCount, 0)
    }

    func test_seed_lastPlayedInAppGroupAlready_doesNotOverwrite() throws {
        let (appGroup, standard) = try makeSuites()
        appGroup.set("file:///existing", forKey: LastPlayedStore.key)
        standard.set("file:///stale", forKey: LastPlayedStore.key)
        appGroup.set(Data(), forKey: LibrarySnapshotWriter.key)

        AppDelegateSeeder(
            lastPlayedSuite: appGroup,
            standard: standard,
            snapshotWriter: MockLibrarySnapshotWriter()
        ).seedIfNeeded()

        XCTAssertEqual(appGroup.string(forKey: LastPlayedStore.key), "file:///existing")
    }
}
