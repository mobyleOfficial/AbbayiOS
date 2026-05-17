//
//  LibrarySnapshotWriterTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class LibrarySnapshotWriterTests: XCTestCase {
    private var testSuite: UserDefaults?
    private var suiteName: String?
    private var mockLoadAllAudios: MockLoadAllAudiosUseCase?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let name = "test.snapshot.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        suite.removePersistentDomain(forName: name)
        suiteName = name
        testSuite = suite
        LibrarySnapshotWriter.defaults = suite
        mockLoadAllAudios = MockLoadAllAudiosUseCase()
    }

    override func tearDownWithError() throws {
        if let name = suiteName, let suite = testSuite {
            suite.removePersistentDomain(forName: name)
        }
        LibrarySnapshotWriter.defaults = AppGroup.defaults
        try super.tearDownWithError()
    }

    private func makeWriter() throws -> LibrarySnapshotWriter {
        let mock = try XCTUnwrap(mockLoadAllAudios)
        return LibrarySnapshotWriter(loadAllAudios: mock)
    }

    func test_write_emptyList_writesEmptyAudios() throws {
        try makeWriter().write(audios: [])
        let suite = try XCTUnwrap(testSuite)
        let data = try XCTUnwrap(suite.data(forKey: LibrarySnapshotWriter.key))
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        XCTAssertEqual(snapshot.version, 1)
        XCTAssertEqual(snapshot.audios.count, 0)
    }

    func test_write_includesBookmarkDataWhenModelPopulated() throws {
        var model = AudioModel(url: URL(string: "file:///book.m4a"))
        model.title = "Title"
        model.bookmarkData = Data([1, 2, 3])

        try makeWriter().write(audios: [model])
        let suite = try XCTUnwrap(testSuite)
        let data = try XCTUnwrap(suite.data(forKey: LibrarySnapshotWriter.key))
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        XCTAssertEqual(snapshot.audios.first?.bookmarkData, Data([1, 2, 3]))
    }

    func test_write_excludesBookmarkDataWhenModelEmpty() throws {
        var model = AudioModel(url: URL(string: "file:///book.m4a"))
        model.title = "Title"
        // bookmarkData nil by default

        try makeWriter().write(audios: [model])
        let suite = try XCTUnwrap(testSuite)
        let data = try XCTUnwrap(suite.data(forKey: LibrarySnapshotWriter.key))
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        XCTAssertNil(snapshot.audios.first?.bookmarkData)
    }

    func test_write_afterDelete_removesEntry() throws {
        var modelA = AudioModel(url: URL(string: "file:///a.m4a"))
        modelA.title = "A"
        var modelB = AudioModel(url: URL(string: "file:///b.m4a"))
        modelB.title = "B"

        let writer = try makeWriter()
        writer.write(audios: [modelA, modelB])
        writer.write(audios: [modelA])

        let suite = try XCTUnwrap(testSuite)
        let data = try XCTUnwrap(suite.data(forKey: LibrarySnapshotWriter.key))
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        XCTAssertEqual(snapshot.audios.count, 1)
        XCTAssertEqual(snapshot.audios.first?.title, "A")
    }
}
