//
//  LibriVoxClientTests.swift
//  AbbayTests
//

@testable import Abbay
import NetworkProvider
import UIKit
import XCTest

/// Search, popular and cover. Details are in `LibriVoxClientDetailsTests`.
final class LibriVoxClientTests: LibriVoxClientTestCase {
    private let oldPopular = Reply(data: Data(#"{"response":{"docs":[{"identifier":"old","title":"Old"}]}}"#.utf8))

    // MARK: - Search

    func test_search_requestsArchiveSearch_mostDownloadedFirst() async throws {
        let reply = try fixture("archive_search_wonderland")
        let (sut, network) = makeSUT { _ in reply }

        _ = try await sut.search("Wonderland")

        let request = try XCTUnwrap(network.requests.first)
        XCTAssertEqual(network.requests.count, 1)
        XCTAssertEqual(request.endpoint, "https://archive.org/advancedsearch.php")
        XCTAssertEqual(request.queryParams?["q"], ArchiveSearchQuery.search("Wonderland"))
        XCTAssertEqual(request.queryParams?["fl[]"], "identifier,title,creator,language,mediatype")
        XCTAssertEqual(request.queryParams?["sort[]"], "downloads desc")
        XCTAssertEqual(request.queryParams?["rows"], "50")
        XCTAssertEqual(request.queryParams?["output"], "json")
    }

    func test_search_mapsLightResults() async throws {
        let reply = try fixture("archive_search_wonderland")
        let (sut, _) = makeSUT { _ in reply }

        let books = try await sut.search("wonderland")

        XCTAssertEqual(books.count, 5)
        let alice = try XCTUnwrap(books.first)
        XCTAssertEqual(alice.id, "alice_in_wonderland_librivox")
        XCTAssertEqual(alice.title, "Alice's Adventures in Wonderland")
        XCTAssertEqual(alice.authors, "Lewis Carroll")
        XCTAssertEqual(alice.language, "eng")
        XCTAssertEqual(alice.coverURL.absoluteString, "https://archive.org/services/img/alice_in_wonderland_librivox")
        XCTAssertTrue(alice.sections.isEmpty)
        XCTAssertEqual(alice.totalSeconds, 0)
    }

    func test_search_isCachedForTheSession_byNormalizedQuery() async throws {
        let reply = try fixture("archive_search_wonderland")
        let (sut, network) = makeSUT { _ in reply }

        let first = try await sut.search("Wonderland")
        let second = try await sut.search("  wonderland ")

        XCTAssertEqual(first, second)
        XCTAssertEqual(network.requests.count, 1)
    }

    func test_search_failureIsNotCached() async throws {
        let reply = try fixture("archive_search_wonderland")
        var fail = true
        let (sut, network) = makeSUT { _ in
            if fail { throw URLError(.notConnectedToInternet) }
            return reply
        }

        _ = try? await sut.search("wonderland")
        fail = false
        let books = try await sut.search("wonderland")

        XCTAssertEqual(books.count, 5)
        XCTAssertEqual(network.requests.count, 2)
    }

    func test_search_blankQuery_returnsEmptyWithoutRequest() async throws {
        let (sut, network) = makeSUT { _ in Reply(data: Data()) }

        let books = try await sut.search("   ")

        XCTAssertEqual(books, [])
        XCTAssertTrue(network.requests.isEmpty)
    }

    func test_search_serverError_throws() async {
        let (sut, _) = makeSUT { _ in Reply(statusCode: 500, data: Data("{}".utf8)) }

        do {
            _ = try await sut.search("alice")
            XCTFail("Expected an error")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func test_search_dropsDocsWithoutIdentifierOrTitle_andNonAudio_andDuplicates() async throws {
        let json = """
        {"response":{"docs":[
        {"identifier":"ok","title":"Ok","creator":["A","B"],"language":["por"],"mediatype":"audio"},
        {"title":"No identifier","mediatype":"audio"},
        {"identifier":"no_title","mediatype":"audio"},
        {"identifier":"cover_art","title":"Thumbs","mediatype":"image"},
        {"identifier":"ok","title":"Ok again","mediatype":"audio"}]}}
        """
        let (sut, _) = makeSUT { _ in Reply(data: Data(json.utf8)) }

        let books = try await sut.search("x")

        XCTAssertEqual(books.map(\.id), ["ok"])
        XCTAssertEqual(books.first?.authors, "A, B")
        XCTAssertEqual(books.first?.language, "por")
    }

    // MARK: - Popular

    func test_popular_requestsAudioCatalog_byDownloads() async throws {
        let reply = try fixture("archive_popular")
        let (sut, network) = makeSUT { _ in reply }

        _ = try await sut.popular()

        let request = try XCTUnwrap(network.requests.first)
        XCTAssertEqual(request.queryParams?["q"], "collection:librivoxaudio AND mediatype:audio")
        XCTAssertEqual(request.queryParams?["sort[]"], "downloads desc")
        XCTAssertEqual(request.queryParams?["rows"], "30")
    }

    /// The fixture comes from the collection without the `mediatype:audio` clause, so it holds the
    /// non-book items the clause keeps out; the client drops them too.
    func test_popular_dropsNonBookItems_keepsOrder() async throws {
        let reply = try fixture("archive_popular")
        let (sut, _) = makeSUT { _ in reply }

        let books = try await sut.popular()

        XCTAssertEqual(books.map(\.id), [
            "art_of_war_librivox", "alice_in_wonderland_librivox", "tom_sawyer_librivox",
            "adventures_holmes", "moby_dick_librivox", "huck_finn_librivox"
        ])
    }

    func test_popular_freshCache_noRequest() async throws {
        let reply = try fixture("archive_popular")
        let (first, _) = makeSUT { _ in reply }
        let stored = try await first.popular()
        now += day - 1
        let (sut, network) = makeSUT { _ in throw URLError(.notConnectedToInternet) }

        let books = try await sut.popular()

        XCTAssertEqual(books, stored)
        XCTAssertTrue(network.requests.isEmpty)
        XCTAssertNil(sut.pendingPopularRefresh)
    }

    func test_popular_staleCache_returnedAtOnce_thenRefreshedInBackground() async throws {
        let (first, _) = makeSUT { _ in self.oldPopular }
        _ = try await first.popular()
        now += day + 1
        let fresh = try fixture("archive_popular")
        let (sut, network) = makeSUT { _ in fresh }

        let books = try await sut.popular()
        await sut.pendingPopularRefresh?.value

        XCTAssertEqual(books.map(\.id), ["old"])
        XCTAssertEqual(network.requests.count, 1)
        let refreshed = cache.read([LibriVoxBook].self, key: LibriVoxClient.popularKey, maxAge: day)
        XCTAssertEqual(refreshed?.isFresh, true)
        XCTAssertEqual(refreshed?.value.first?.id, "art_of_war_librivox")
    }

    func test_popular_staleCache_networkFails_keepsStaleList() async throws {
        let (first, _) = makeSUT { _ in self.oldPopular }
        _ = try await first.popular()
        now += 3 * day
        let (sut, _) = makeSUT { _ in throw URLError(.notConnectedToInternet) }

        let books = try await sut.popular()
        await sut.pendingPopularRefresh?.value
        let again = try await sut.popular()

        XCTAssertEqual(books.map(\.id), ["old"])
        XCTAssertEqual(again.map(\.id), ["old"])
    }

    func test_popular_noCache_networkFails_throws() async {
        let (sut, _) = makeSUT { _ in throw URLError(.notConnectedToInternet) }

        do {
            _ = try await sut.popular()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    // MARK: - Cover


    func test_coverData_returnsBytesOnSuccess_andNilOnFailure() async throws {
        let cover = Self.png()
        var succeed = true
        let (sut, network) = makeSUT { _ in
            succeed ? Reply(data: cover) : Reply(statusCode: 404, data: Data())
        }
        let other = LibriVoxBook.light(id: "other", coverURL: try XCTUnwrap(LibriVoxBook.coverURL(for: "other")))

        let ok = await sut.coverData(for: try aliceWithCover())
        succeed = false
        let failed = await sut.coverData(for: other)

        XCTAssertEqual(ok, cover)
        XCTAssertNil(failed)
        XCTAssertEqual(network.requests.first?.endpoint, "https://archive.org/services/img/alice_in_wonderland_librivox")
    }

    /// The details page already loaded the cover, so saving the book reads it from the covers'
    /// disk cache instead of downloading it again (#175).
    func test_coverData_whenTheCoverIsOnDisk_makesNoRequest() async throws {
        let book = try aliceWithCover()
        let cover = Self.png()
        coverDisk.store(cover, for: book.coverURL)
        let (sut, network) = makeSUT { request in
            XCTFail("no request expected, got \(request.endpoint)")
            return Reply(data: Data())
        }

        let data = await sut.coverData(for: book)

        XCTAssertEqual(data, cover)
        XCTAssertEqual(network.requests.count, 0)
    }

    /// A downloaded cover is stored, so the loader shows it next time without a request.
    func test_coverData_storesTheDownloadOnDisk() async throws {
        let book = try aliceWithCover()
        let cover = Self.png()
        let (sut, _) = makeSUT { _ in Reply(data: cover) }

        _ = await sut.coverData(for: book)

        XCTAssertEqual(coverDisk.data(for: book.coverURL), cover)
    }

    /// The host allowlist applies to the saved cover too: anything off it is refused unfetched (#175).
    func test_coverData_fromADisallowedHost_isNil_withoutARequest() async throws {
        let refused = [
            "https://example.com/cover.jpg",
            "http://archive.org/services/img/alice",
            "file:///dev/null/cover.jpg"
        ]
        let cover = Self.png()
        let (sut, network) = makeSUT { _ in Reply(data: cover) }

        for string in refused {
            let book = LibriVoxBook.light(id: "alice", coverURL: try XCTUnwrap(URL(string: string)))
            let data = await sut.coverData(for: book)
            XCTAssertNil(data, string)
        }

        XCTAssertEqual(network.requests.count, 0)
    }

    func test_coverData_whenTheBodyIsNotAnImage_isNil() async throws {
        let (sut, _) = makeSUT { _ in Reply(data: Data([1, 2, 3])) }

        let data = await sut.coverData(for: try aliceWithCover())

        XCTAssertNil(data)
    }

    private func aliceWithCover() throws -> LibriVoxBook {
        LibriVoxBook.light(
            id: "alice_in_wonderland_librivox",
            coverURL: try XCTUnwrap(LibriVoxBook.coverURL(for: "alice_in_wonderland_librivox"))
        )
    }

    private static func png() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format)
        return renderer.pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}
