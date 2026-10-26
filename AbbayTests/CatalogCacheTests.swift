//
//  CatalogCacheTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class CatalogCacheTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory
    private var now = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeSUT() -> CatalogCache {
        CatalogCache(directory: directory) { [unowned self] in now }
    }

    func test_read_missingKey_isNil() {
        XCTAssertNil(makeSUT().read([String].self, key: "nothing", maxAge: 60))
    }

    func test_write_thenRead_isFreshWithinMaxAge() throws {
        let sut = makeSUT()
        sut.write(["a", "b"], key: "list")
        now += 59

        let hit = try XCTUnwrap(sut.read([String].self, key: "list", maxAge: 60))

        XCTAssertEqual(hit.value, ["a", "b"])
        XCTAssertTrue(hit.isFresh)
        XCTAssertEqual(hit.storedAt, Date(timeIntervalSince1970: 1_000_000))
    }

    func test_read_afterMaxAge_isStaleButStillReturned() throws {
        let sut = makeSUT()
        sut.write(["a"], key: "list")
        now += 61

        let hit = try XCTUnwrap(sut.read([String].self, key: "list", maxAge: 60))

        XCTAssertEqual(hit.value, ["a"])
        XCTAssertFalse(hit.isFresh)
    }

    func test_persistsAcrossInstances() {
        makeSUT().write(["kept"], key: "list")

        XCTAssertEqual(makeSUT().read([String].self, key: "list", maxAge: 60)?.value, ["kept"])
    }

    func test_overwrite_resetsTimestamp() throws {
        let sut = makeSUT()
        sut.write(["old"], key: "k")
        now += 100
        sut.write(["new"], key: "k")

        let hit = try XCTUnwrap(sut.read([String].self, key: "k", maxAge: 60))

        XCTAssertEqual(hit.value, ["new"])
        XCTAssertTrue(hit.isFresh)
    }

    func test_remove() {
        let sut = makeSUT()
        sut.write(["a"], key: "k")

        sut.remove(key: "k")

        XCTAssertNil(sut.read([String].self, key: "k", maxAge: 60))
    }

    func test_keysWithPathCharacters_stayInsideDirectory() throws {
        let sut = makeSUT()
        sut.write(["x"], key: "../../escape/é")

        XCTAssertEqual(sut.read([String].self, key: "../../escape/é", maxAge: 60)?.value, ["x"])
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 1)
    }

    func test_wrongType_isNil() {
        let sut = makeSUT()
        sut.write(["a"], key: "k")

        XCTAssertNil(sut.read(Int.self, key: "k", maxAge: 60))
    }

    func test_defaultDirectory_isInCaches() {
        XCTAssertTrue(CatalogCache.defaultDirectory.path.contains("/Library/Caches/"))
    }
}
