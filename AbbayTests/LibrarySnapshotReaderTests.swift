//
//  LibrarySnapshotReaderTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class LibrarySnapshotReaderTests: XCTestCase {
    private var testSuite: UserDefaults?
    private var suiteName: String?
    private var mockLoadAllAudios: MockLoadAllAudiosUseCase?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let name = "test.snapshot-read.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        suite.removePersistentDomain(forName: name)
        suiteName = name
        testSuite = suite
        mockLoadAllAudios = MockLoadAllAudiosUseCase()
    }

    override func tearDownWithError() throws {
        if let name = suiteName, let suite = testSuite {
            suite.removePersistentDomain(forName: name)
        }
        try super.tearDownWithError()
    }

    private func makeReader() throws -> LibrarySnapshotReader {
        LibrarySnapshotReader(store: try XCTUnwrap(testSuite))
    }

    func test_read_missingValue_returnsEmpty() throws {
        XCTAssertEqual(try makeReader().read(), [])
    }

    func test_read_malformedJSON_returnsEmpty() throws {
        let suite = try XCTUnwrap(testSuite)
        suite.set(Data("not-json".utf8), forKey: LibrarySnapshotWriter.key)
        XCTAssertEqual(try makeReader().read(), [])
    }

    func test_write_decodableByReader_roundTrip() throws {
        var modelA = AudioModel(url: URL(string: "file:///a.m4a"))
        modelA.title = "Sorcerer's Stone"
        modelA.bookmarkData = Data([1, 2])
        var modelB = AudioModel(url: URL(string: "file:///b.m4a"))
        modelB.title = "Chamber of Secrets"

        let mock = try XCTUnwrap(mockLoadAllAudios)
        let writer = LibrarySnapshotWriter(
            store: try XCTUnwrap(testSuite),
            loadAllAudios: mock,
            publisher: NoopSiriLibraryPublisher()
        )
        writer.write(audios: [modelA, modelB])
        let entries = try makeReader().read()

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].title, "Sorcerer's Stone")
        XCTAssertEqual(entries[0].urlString, "file:///a.m4a")
        XCTAssertEqual(entries[0].bookmarkData, Data([1, 2]))
        XCTAssertEqual(entries[1].title, "Chamber of Secrets")
        XCTAssertNil(entries[1].bookmarkData)
    }
}
