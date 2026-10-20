//
//  URLSecurityScopedTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Covers the bookmark layer that makes `asCopy: false` imports survive a relaunch. This is the
/// code that breaks when a user moves or renames an imported file, and it had no tests.
final class URLSecurityScopedTests: XCTestCase {
    // MARK: - createBookmarkData

    func test_createBookmarkData_realFile_returnsData() throws {
        let url = try TestFixtures.christmastideURL()

        let data = url.createBookmarkData()

        XCTAssertNotNil(data)
        XCTAssertFalse(try XCTUnwrap(data).isEmpty)
    }

    func test_createBookmarkData_missingFile_returnsNil() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).m4b")

        XCTAssertNil(url.createBookmarkData(), "a bookmark to a missing file cannot be created")
    }

    // MARK: - resolveBookmark

    func test_resolveBookmark_roundTripsToTheSameFile() throws {
        let url = try TestFixtures.christmastideURL()
        let data = try XCTUnwrap(url.createBookmarkData())

        let resolved = URL.resolveBookmark(from: data)

        XCTAssertEqual(
            try XCTUnwrap(resolved).standardizedFileURL,
            url.standardizedFileURL,
            "a freshly created bookmark must resolve back to its origin"
        )
    }

    func test_resolveBookmark_nilData_returnsNil() {
        XCTAssertNil(URL.resolveBookmark(from: nil))
    }

    func test_resolveBookmark_garbageData_returnsNilRatherThanThrowing() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF])

        XCTAssertNil(
            URL.resolveBookmark(from: garbage),
            "a corrupt bookmark must degrade to nil, not crash"
        )
    }

    func test_resolveBookmark_emptyData_returnsNil() {
        XCTAssertNil(URL.resolveBookmark(from: Data()))
    }

    // MARK: - BookmarkProvider

    /// `BookmarkProvider` is a second, independent implementation of the same idea: it wraps the
    /// scope access and uses `.minimalBookmark`, where `URL.createBookmarkData()` uses `[]`.
    /// Both must round-trip.
    func test_bookmarkProvider_roundTripsToTheSameFile() throws {
        let url = try TestFixtures.christmastideURL()
        let data = try XCTUnwrap(BookmarkProvider().createBookmarkData(for: url))

        let resolved = try XCTUnwrap(URL.resolveBookmark(from: data))

        XCTAssertEqual(resolved.standardizedFileURL, url.standardizedFileURL)
    }

    func test_bookmarkProvider_missingFile_returnsNil() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).m4b")

        XCTAssertNil(BookmarkProvider().createBookmarkData(for: url))
    }
}
