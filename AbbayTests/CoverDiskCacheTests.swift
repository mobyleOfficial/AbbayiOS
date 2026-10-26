//
//  CoverDiskCacheTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Cover bytes on disk, one file per URL, trimmed oldest-used first once over the byte limit.
final class CoverDiskCacheTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory
    private var now = Date(timeIntervalSince1970: 1_000_000)

    private let first = URL(string: "https://archive.org/services/img/first")
    private let second = URL(string: "https://archive.org/services/img/second")
    private let third = URL(string: "https://archive.org/services/img/third")

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeSUT(byteLimit: Int = 1000) -> CoverDiskCache {
        CoverDiskCache(directory: directory, byteLimit: byteLimit) { [unowned self] in now }
    }

    private func bytes(_ count: Int) -> Data {
        Data(repeating: 7, count: count)
    }

    // MARK: - Read and write

    func test_data_missingURL_isNil() throws {
        XCTAssertNil(makeSUT().data(for: try XCTUnwrap(first)))
    }

    func test_store_thenData_returnsTheBytes() throws {
        let url = try XCTUnwrap(first)
        let sut = makeSUT()

        sut.store(bytes(10), for: url)

        XCTAssertEqual(sut.data(for: url), bytes(10))
    }

    func test_store_survivesANewInstance_onTheSameDirectory() throws {
        let url = try XCTUnwrap(first)
        makeSUT().store(bytes(10), for: url)

        XCTAssertEqual(makeSUT().data(for: url), bytes(10))
    }

    func test_entries_areKeptPerURL() throws {
        let sut = makeSUT()
        sut.store(bytes(10), for: try XCTUnwrap(first))
        sut.store(bytes(20), for: try XCTUnwrap(second))

        XCTAssertEqual(sut.data(for: try XCTUnwrap(first)), bytes(10))
        XCTAssertEqual(sut.data(for: try XCTUnwrap(second)), bytes(20))
    }

    func test_remove_deletesTheEntry() throws {
        let url = try XCTUnwrap(first)
        let sut = makeSUT()
        sut.store(bytes(10), for: url)

        sut.remove(for: url)

        XCTAssertNil(sut.data(for: url))
    }

    func test_fileNames_holdNoPartOfTheURL() throws {
        let sut = makeSUT()
        sut.store(bytes(10), for: try XCTUnwrap(first))

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        XCTAssertEqual(names.count, 1)
        XCTAssertFalse(names[0].contains("archive"))
        XCTAssertFalse(names[0].contains("first"))
    }

    // MARK: - Size bound

    func test_store_overTheLimit_dropsTheLeastRecentlyUsed() throws {
        let sut = makeSUT(byteLimit: 100)
        sut.store(bytes(40), for: try XCTUnwrap(first))
        now += 1
        sut.store(bytes(40), for: try XCTUnwrap(second))
        now += 1

        sut.store(bytes(40), for: try XCTUnwrap(third))

        XCTAssertNil(sut.data(for: try XCTUnwrap(first)))
        XCTAssertNotNil(sut.data(for: try XCTUnwrap(second)))
        XCTAssertNotNil(sut.data(for: try XCTUnwrap(third)))
    }

    func test_data_marksTheEntryAsRecentlyUsed() throws {
        let sut = makeSUT(byteLimit: 100)
        sut.store(bytes(40), for: try XCTUnwrap(first))
        now += 1
        sut.store(bytes(40), for: try XCTUnwrap(second))
        now += 1
        _ = sut.data(for: try XCTUnwrap(first))
        now += 1

        sut.store(bytes(40), for: try XCTUnwrap(third))

        XCTAssertNotNil(sut.data(for: try XCTUnwrap(first)))
        XCTAssertNil(sut.data(for: try XCTUnwrap(second)))
    }

    func test_store_aSingleEntryOverTheLimit_isNotKept() throws {
        let url = try XCTUnwrap(first)
        let sut = makeSUT(byteLimit: 100)

        sut.store(bytes(101), for: url)

        XCTAssertNil(sut.data(for: url))
    }

    // MARK: - Clear

    func test_removeAll_emptiesTheCache() throws {
        let sut = makeSUT()
        sut.store(bytes(10), for: try XCTUnwrap(first))
        sut.store(bytes(10), for: try XCTUnwrap(second))

        sut.removeAll()

        XCTAssertNil(sut.data(for: try XCTUnwrap(first)))
        XCTAssertNil(sut.data(for: try XCTUnwrap(second)))
    }
}
