//
//  LibrarySnapshotReaderTests.swift
//  AbbayIntentsTests
//

import XCTest

// NOTE: AbbayIntents source files are compiled directly into this test bundle
// (see project.yml). We do NOT `@testable import AbbayIntents` because an
// app-extension binary cannot be linked into a unit-test bundle.

final class ExtensionLibrarySnapshotReaderTests: XCTestCase {
    private var testSuite: UserDefaults?
    private var suiteName: String?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let name = "test.ext-snapshot-read.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        suite.removePersistentDomain(forName: name)
        suiteName = name
        testSuite = suite
    }

    override func tearDownWithError() throws {
        if let name = suiteName, let suite = testSuite {
            suite.removePersistentDomain(forName: name)
        }
        try super.tearDownWithError()
    }

    func test_read_missingValue_returnsEmpty() throws {
        XCTAssertEqual(LibrarySnapshotReader(store: try XCTUnwrap(testSuite)).read(), [])
    }

    func test_extensionReadsMainAppWrite_roundTrip() throws {
        var modelA = AudioModel(url: URL(string: "file:///a"))
        modelA.title = "Sorcerer's Stone"

        let suite = try XCTUnwrap(testSuite)
        LibrarySnapshotWriter(store: suite).write(audios: [modelA])
        let entries = LibrarySnapshotReader(store: suite).read()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].title, "Sorcerer's Stone")
    }
}
