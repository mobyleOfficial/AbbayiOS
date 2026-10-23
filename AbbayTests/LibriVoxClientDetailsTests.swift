//
//  LibriVoxClientDetailsTests.swift
//  AbbayTests
//

@testable import Abbay
import NetworkProvider
import XCTest

/// `details(for:)`: the LibriVox match, the archive.org fallback and the cache.
final class LibriVoxClientDetailsTests: LibriVoxClientTestCase {
    private let aliceMapping = LibriVoxClient.mappingKey("alice_in_wonderland_librivox")

    // MARK: - Details: matched on LibriVox

    func test_details_matched_usesLibriVoxSections_andArchiveSizes() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let carroll = try fixture("librivox_author_carroll")
        let (sut, network) = makeSUT(router(metadata: metadata, feed: { _ in carroll }))

        let details = try await sut.details(for: light("alice_in_wonderland_librivox"))

        let book = details.book
        XCTAssertEqual(book.id, "alice_in_wonderland_librivox")
        XCTAssertEqual(book.title, "Alice's Adventures in Wonderland")
        XCTAssertEqual(book.authors, "Lewis Carroll")
        XCTAssertEqual(book.language, "eng")
        XCTAssertEqual(book.sections.count, 12)
        XCTAssertEqual(book.sections.first?.title, "Chapter 1")
        XCTAssertEqual(book.sections.first?.seconds, 640)
        XCTAssertEqual(
            book.sections.first?.listenURL.absoluteString,
            "https://www.archive.org/download/alice_in_wonderland_librivox/wonderland_ch_01_64kb.mp3"
        )
        XCTAssertEqual(book.totalSeconds, book.sections.reduce(0) { $0 + $1.seconds })
        XCTAssertTrue(book.descriptionText.hasPrefix("In this children's classic, a girl named Alice"))
        XCTAssertEqual(details.sectionBytes.count, 12)
        XCTAssertEqual(details.totalBytes, 85_862_932)
        XCTAssertEqual(network.requests.first?.endpoint, "https://archive.org/metadata/alice_in_wonderland_librivox")
        let feed = try XCTUnwrap(feedRequests(network).first)
        XCTAssertEqual(feed["author"], "Carroll")
        XCTAssertEqual(feed["limit"], "100")
        XCTAssertEqual(feed["offset"], "0")
        XCTAssertEqual(feed["extended"], "1")
        XCTAssertEqual(feed["fields"], "{id,url_iarchive,sections,description}")
    }

    func test_details_matched_storesMappingPermanently() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let carroll = try fixture("librivox_author_carroll")
        let (sut, _) = makeSUT(router(metadata: metadata, feed: { _ in carroll }))

        _ = try await sut.details(for: light("alice_in_wonderland_librivox"))
        now += 365 * day

        let mapping = cache.read(LibriVoxClient.Mapping.self, key: aliceMapping, maxAge: 7 * day)
        XCTAssertEqual(mapping?.value, LibriVoxClient.Mapping(librivoxID: "200"))
    }

    func test_details_knownMapping_fetchesByID_withoutAuthorLookup() async throws {
        cache.write(LibriVoxClient.Mapping(librivoxID: "200"), key: aliceMapping)
        now += 365 * day
        let metadata = try fixture("archive_alice_metadata")
        let carroll = try fixture("librivox_author_carroll")
        let (sut, network) = makeSUT(router(metadata: metadata, feed: { _ in carroll }))

        let details = try await sut.details(for: light("alice_in_wonderland_librivox"))

        XCTAssertEqual(details.book.sections.first?.title, "Chapter 1")
        XCTAssertEqual(feedRequests(network).map { $0["id"] }, ["200"])
        XCTAssertNil(feedRequests(network).first?["author"])
    }

    /// The owner's question: "what happens if an id is deleted?" The mapping is dropped and the
    /// author lookup finds the book again.
    func test_details_knownMappingDeleted_looksUpByAuthorAgain() async throws {
        cache.write(LibriVoxClient.Mapping(librivoxID: "999999"), key: aliceMapping)
        let metadata = try fixture("archive_alice_metadata")
        let carroll = try fixture("librivox_author_carroll")
        let notFound = try fixture("not_found", status: 404)
        let (sut, network) = makeSUT(router(metadata: metadata, feed: { request in
            request.queryParams?["id"] != nil ? notFound : carroll
        }))

        let details = try await sut.details(for: light("alice_in_wonderland_librivox"))

        XCTAssertEqual(details.book.sections.first?.title, "Chapter 1")
        XCTAssertEqual(feedRequests(network).map { $0["id"] ?? $0["author"] }, ["999999", "Carroll"])
        let mapping = cache.read(LibriVoxClient.Mapping.self, key: aliceMapping, maxAge: day)
        XCTAssertEqual(mapping?.value.librivoxID, "200")
    }

    // MARK: - Details: fallback to archive.org files

    /// "Various" can't be looked up by last name (a live lookup reads 3 slow pages for nothing).
    func test_details_variousCreator_skipsLookup_fallsBackToArchiveFiles() async throws {
        let metadata = try fixture("archive_1891_metadata")
        let various = try fixture("librivox_author_various")
        let (sut, network) = makeSUT(router(metadata: metadata, feed: { _ in various }))

        let details = try await sut.details(for: light("1891_collection_bt_librivox"))

        let book = details.book
        XCTAssertTrue(feedRequests(network).isEmpty)
        let mappingKey = LibriVoxClient.mappingKey("1891_collection_bt_librivox")
        let mapping = cache.read(LibriVoxClient.Mapping.self, key: mappingKey, maxAge: day)
        XCTAssertEqual(mapping?.value, .init(librivoxID: nil))
        XCTAssertEqual(book.title, "1891 Collection")
        XCTAssertTrue(book.descriptionText.hasPrefix("LibriVox recording of 1891 Collection by Various."))
        XCTAssertEqual(book.sections.count, 10)
        XCTAssertEqual(book.sections.first?.title, "01 - Impressions of American Hotels by Max O'Rell")
        XCTAssertEqual(book.sections.first?.seconds, 989)
        XCTAssertEqual(book.sections[1].seconds, 3655)
        XCTAssertEqual(
            book.sections.first?.listenURL.absoluteString,
            "https://archive.org/download/1891_collection_bt_librivox/1891collection_01_64kb.mp3"
        )
        XCTAssertEqual(details.sectionBytes.first, 7_920_640)
        XCTAssertEqual(book.totalSeconds, book.sections.reduce(0) { $0 + $1.seconds })
    }

    func test_details_noMatch_pagesUpToTheCap_thenStops() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let page = unrelatedPage()
        let (sut, network) = makeSUT(router(metadata: metadata, feed: { _ in page }))

        let details = try await sut.details(for: light("alice_in_wonderland_librivox"))

        XCTAssertEqual(feedRequests(network).first?["offset"], "0")
        XCTAssertEqual(Set(feedRequests(network).compactMap { $0["offset"] }), ["0", "100", "200"])
        XCTAssertEqual(feedRequests(network).count, 3)
        XCTAssertEqual(details.book.sections.first?.title, "wonderland_ch_01")
        XCTAssertEqual(details.book.sections.count, 12)
        let mapping = cache.read(LibriVoxClient.Mapping.self, key: aliceMapping, maxAge: day)
        XCTAssertEqual(mapping?.value, .init(librivoxID: nil))
    }

    func test_details_matchOnALaterPage_isFound() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let page = unrelatedPage()
        let carroll = try fixture("librivox_author_carroll")
        let (sut, _) = makeSUT(router(metadata: metadata, feed: { request in
            request.queryParams?["offset"] == "200" ? carroll : page
        }))

        let details = try await sut.details(for: light("alice_in_wonderland_librivox"))

        XCTAssertEqual(details.book.sections.first?.title, "Chapter 1")
        XCTAssertEqual(cache.read(LibriVoxClient.Mapping.self, key: aliceMapping, maxAge: day)?.value.librivoxID, "200")
    }

    func test_details_laterPageFails_withoutMatch_isUnavailable_noMissCached() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let page = unrelatedPage()
        let (sut, _) = makeSUT(router(metadata: metadata, feed: { request in
            if request.queryParams?["offset"] == "100" { throw URLError(.timedOut) }
            return page
        }))

        let details = try await sut.details(for: light("alice_in_wonderland_librivox"))

        XCTAssertEqual(details.book.sections.first?.title, "wonderland_ch_01")
        XCTAssertNil(cache.read(LibriVoxClient.Mapping.self, key: aliceMapping, maxAge: day))
    }

    func test_details_noMatch_shortPageStopsPaging() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let page = unrelatedPage(size: 99)
        let (sut, network) = makeSUT(router(metadata: metadata, feed: { _ in page }))

        _ = try await sut.details(for: light("alice_in_wonderland_librivox"))

        XCTAssertEqual(feedRequests(network).count, 1)
    }

    /// The Various fixture is a real short page that doesn't list Alice.
    func test_details_noMatch_negativeMappingSkipsLookupForSevenDays() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let noAlice = try fixture("librivox_author_various")
        let (sut, network) = makeSUT(router(metadata: metadata, feed: { _ in noAlice }))
        let detailsKey = LibriVoxClient.detailsKey("alice_in_wonderland_librivox")
        _ = try await sut.details(for: light("alice_in_wonderland_librivox"))
        XCTAssertEqual(
            cache.read(LibriVoxClient.Mapping.self, key: aliceMapping, maxAge: day)?.value,
            LibriVoxClient.Mapping(librivoxID: nil)
        )
        cache.remove(key: detailsKey)

        now += 7 * day - 1
        _ = try await sut.details(for: light("alice_in_wonderland_librivox"))
        XCTAssertEqual(feedRequests(network).count, 1)

        cache.remove(key: detailsKey)
        now += 2
        _ = try await sut.details(for: light("alice_in_wonderland_librivox"))
        XCTAssertEqual(feedRequests(network).count, 2)
    }

    func test_details_libriVoxTimeout_fallsBack_butCachesNeitherDetailsNorMiss() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let (sut, network) = makeSUT(router(metadata: metadata, feed: { _ in throw URLError(.timedOut) }))

        let details = try await sut.details(for: light("alice_in_wonderland_librivox"))

        let feed = network.requests.filter { $0.endpoint == LibriVoxRequests.feedEndpoint }
        XCTAssertEqual(feed.count, 1)
        XCTAssertEqual(feed.first?.timeoutInterval, 5)

        XCTAssertEqual(details.book.sections.first?.title, "wonderland_ch_01")
        let detailsKey = LibriVoxClient.detailsKey("alice_in_wonderland_librivox")
        XCTAssertNil(cache.read(LibriVoxBookDetails.self, key: detailsKey, maxAge: day))
        XCTAssertNil(cache.read(LibriVoxClient.Mapping.self, key: aliceMapping, maxAge: day))
    }

    func test_details_missingCreator_fallsBackWithoutLookup() async throws {
        let json = """
        {"metadata":{"title":"Anon","mediatype":"audio"},
         "files":[{"name":"b_64kb.mp3","format":"64Kbps MP3","size":"2","length":"95.5","track":"2"},
                  {"name":"a_64kb.mp3","format":"64Kbps MP3","size":"1","length":"1:00","track":"1"}]}
        """
        let (sut, network) = makeSUT(router(metadata: Reply(data: Data(json.utf8))))

        let details = try await sut.details(for: light("anon"))

        XCTAssertTrue(feedRequests(network).isEmpty)
        XCTAssertNotNil(cache.read(LibriVoxClient.Mapping.self, key: "mapping.anon", maxAge: day))
        XCTAssertEqual(details.book.sections.map(\.title), ["a_64kb", "b_64kb"])
        XCTAssertEqual(details.book.sections.map(\.seconds), [60, 95.5])
        XCTAssertEqual(details.sectionBytes, [1, 2])
        XCTAssertEqual(details.book.authors, "")
    }

    func test_details_variousIsCaseInsensitive() async throws {
        let json = """
        {"metadata":{"title":"Short Works","creator":" VARIOUS ","mediatype":"audio"},
         "files":[{"name":"a_64kb.mp3","format":"64Kbps MP3","size":"1","length":"1:00","track":"1"}]}
        """
        let metadata = Reply(data: Data(json.utf8))
        let (sut, network) = makeSUT(router(metadata: metadata, feed: { _ in self.unrelatedPage() }))

        _ = try await sut.details(for: light("short_works"))

        XCTAssertTrue(feedRequests(network).isEmpty)
    }

    func test_details_matched_zeroOrEmptyPlaytime_usesArchiveFileLength() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let base = "https://www.archive.org/download/alice_in_wonderland_librivox/"
        let feedJSON = """
        {"books":[{"id":"200","url_iarchive":"https://www.archive.org/details/alice_in_wonderland_librivox",
         "sections":[{"title":"Chapter 1","listen_url":"\(base)wonderland_ch_01_64kb.mp3","playtime":"0"},
                     {"title":"Chapter 2","listen_url":"\(base)wonderland_ch_02_64kb.mp3","playtime":""},
                     {"title":"Chapter 3","listen_url":"\(base)wonderland_ch_03_64kb.mp3","playtime":"1000"}]}]}
        """
        let (sut, _) = makeSUT(router(metadata: metadata, feed: { _ in Reply(data: Data(feedJSON.utf8)) }))

        let details = try await sut.details(for: light("alice_in_wonderland_librivox"))

        XCTAssertEqual(details.book.sections.map(\.title), ["Chapter 1", "Chapter 2", "Chapter 3"])
        XCTAssertEqual(details.book.sections.map(\.seconds), [640, 735, 1000])
    }

    func test_details_notAudio_throws() async throws {
        let image = #"{"metadata":{"title":"Thumbs","mediatype":"image"},"files":[]}"#
        let empty = "{}"
        let noFiles = #"{"metadata":{"title":"None","mediatype":"audio"},"files":[{"name":"a.txt","format":"Text"}]}"#
        for json in [image, empty, noFiles] {
            let metadata = Reply(data: Data(json.utf8))
            let (sut, _) = makeSUT(router(metadata: metadata, feed: { _ in self.unrelatedPage(size: 0) }))
            do {
                _ = try await sut.details(for: light("thing"))
                XCTFail("Expected an error for \(json)")
            } catch {
                XCTAssertEqual(error as? LibriVoxClientError, .notAnAudiobook, json)
            }
        }
    }

    // MARK: - Details: cache

    func test_details_freshCache_noRequest() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let carroll = try fixture("librivox_author_carroll")
        let (first, _) = makeSUT(router(metadata: metadata, feed: { _ in carroll }))
        let stored = try await first.details(for: light("alice_in_wonderland_librivox"))
        now += 7 * day - 1
        let (sut, network) = makeSUT { _ in throw URLError(.notConnectedToInternet) }

        let details = try await sut.details(for: light("alice_in_wonderland_librivox"))

        XCTAssertEqual(details, stored)
        XCTAssertTrue(network.requests.isEmpty)
    }

    func test_details_expired_refetches() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let carroll = try fixture("librivox_author_carroll")
        let (first, _) = makeSUT(router(metadata: metadata, feed: { _ in carroll }))
        _ = try await first.details(for: light("alice_in_wonderland_librivox"))
        now += 7 * day + 1
        let (sut, network) = makeSUT(router(metadata: metadata, feed: { _ in carroll }))

        _ = try await sut.details(for: light("alice_in_wonderland_librivox"))

        XCTAssertEqual(network.requests.first?.endpoint, "https://archive.org/metadata/alice_in_wonderland_librivox")
        XCTAssertEqual(feedRequests(network).map { $0["id"] }, ["200"])
    }

    func test_details_expired_networkFails_returnsStale() async throws {
        let metadata = try fixture("archive_alice_metadata")
        let carroll = try fixture("librivox_author_carroll")
        let (first, _) = makeSUT(router(metadata: metadata, feed: { _ in carroll }))
        let stored = try await first.details(for: light("alice_in_wonderland_librivox"))
        now += 30 * day
        let (sut, _) = makeSUT { _ in throw URLError(.notConnectedToInternet) }

        let details = try await sut.details(for: light("alice_in_wonderland_librivox"))

        XCTAssertEqual(details, stored)
    }

    func test_details_noCache_networkFails_throws() async {
        let (sut, _) = makeSUT { _ in throw URLError(.notConnectedToInternet) }

        do {
            _ = try await sut.details(for: light("alice_in_wonderland_librivox"))
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }
}
