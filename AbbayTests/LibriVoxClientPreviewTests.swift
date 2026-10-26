//
//  LibriVoxClientPreviewTests.swift
//  AbbayTests
//

@testable import Abbay
import NetworkProvider
import XCTest

/// `details(for:onPreview:)` (#258): archive.org's version first, LibriVox's after, and the
/// lookup started from the search result's creator.
final class LibriVoxClientPreviewTests: LibriVoxClientTestCase {
    @MainActor
    func test_details_preview_isArchiveOnly_thenTheFinalHasLibriVoxTitles() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let carroll = try fixture("librivox_author_carroll")
        let (sut, _) = makeSUT(router(metadata: metadata, feed: { _ in carroll }))
        let previews = PreviewLog()

        let details = try await sut.details(for: light("alice_in_wonderland_librivox")) { previews.append($0) }

        let preview = try XCTUnwrap(previews.only)
        XCTAssertEqual(preview.book.sections.first?.title, "wonderland_ch_01")
        XCTAssertEqual(preview.book.sections.count, details.book.sections.count)
        XCTAssertEqual(preview.totalBytes, details.totalBytes)
        XCTAssertEqual(details.book.sections.first?.title, "Chapter 1")
    }

    @MainActor
    func test_details_freshCache_returnsAtOnce_withoutAPreview() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let carroll = try fixture("librivox_author_carroll")
        let (sut, network) = makeSUT(router(metadata: metadata, feed: { _ in carroll }))
        _ = try await sut.details(for: light("alice_in_wonderland_librivox"))
        let requests = network.requests.count
        let previews = PreviewLog()

        let again = try await sut.details(for: light("alice_in_wonderland_librivox")) { previews.append($0) }

        XCTAssertNil(previews.only)
        XCTAssertEqual(network.requests.count, requests)
        XCTAssertEqual(again.book.sections.first?.title, "Chapter 1")
    }

    @MainActor
    func test_details_expiredCache_isThePreview_notTheFileNames() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let carroll = try fixture("librivox_author_carroll")
        let (sut, _) = makeSUT(router(metadata: metadata, feed: { _ in carroll }))
        _ = try await sut.details(for: light("alice_in_wonderland_librivox"))
        now += 8 * day
        let previews = PreviewLog()

        _ = try await sut.details(for: light("alice_in_wonderland_librivox")) { previews.append($0) }

        XCTAssertEqual(try XCTUnwrap(previews.only).book.sections.first?.title, "Chapter 1")
    }

    func test_details_bookWithCreator_looksUpByThatCreator_andMatches() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let carroll = try fixture("librivox_author_carroll")
        let (sut, network) = makeSUT(router(metadata: metadata, feed: { _ in carroll }))
        var book = light("alice_in_wonderland_librivox")
        book.creator = "Lewis Carroll"

        let details = try await sut.details(for: book)

        XCTAssertEqual(details.book.sections.first?.title, "Chapter 1")
        XCTAssertEqual(details.book.creator, "Lewis Carroll")
        XCTAssertEqual(feedRequests(network).map { $0["author"] }, ["Carroll"])
    }

    func test_details_creatorDiffersFromArchive_looksUpArchivesCreator() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let carroll = try fixture("librivox_author_carroll")
        let (sut, network) = makeSUT(router(metadata: metadata, feed: { request in
            request.queryParams?["author"] == "Carroll" ? carroll : self.unrelatedPage(size: 3)
        }))
        var book = light("alice_in_wonderland_librivox")
        book.creator = "Someone Else"

        let details = try await sut.details(for: book)

        XCTAssertEqual(details.book.sections.first?.title, "Chapter 1")
        XCTAssertTrue(feedRequests(network).contains { $0["author"] == "Carroll" })
    }

    func test_details_earlyLookupWithTheWrongCreator_recordsNoMiss() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let (sut, _) = makeSUT(router(metadata: metadata, feed: { _ in self.unrelatedPage(size: 3) }))
        var book = light("alice_in_wonderland_librivox")
        book.creator = "Someone Else"

        _ = try await sut.details(for: book)

        // Carroll (archive.org's creator) found nothing either, so a miss is recorded: for Carroll.
        let key = LibriVoxClient.mappingKey("alice_in_wonderland_librivox")
        XCTAssertEqual(cache.read(LibriVoxClient.Mapping.self, key: key, maxAge: day)?.value.librivoxID, nil)
    }
}

/// The previews a `details(for:onPreview:)` call delivered, in order.
@MainActor
private final class PreviewLog {
    private(set) var all = [LibriVoxBookDetails]()

    func append(_ details: LibriVoxBookDetails) { all.append(details) }
    /// The single preview, or nil when there were none (a test failure when more than one).
    var only: LibriVoxBookDetails? {
        XCTAssertLessThanOrEqual(all.count, 1)
        return all.first
    }
}
