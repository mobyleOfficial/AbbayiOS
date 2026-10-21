//
//  LibriVoxClientTests.swift
//  AbbayTests
//

@testable import Abbay
import NetworkProvider
import XCTest

final class LibriVoxClientTests: XCTestCase {
    private let notFound = MockNetworkProvider.Reply(
        statusCode: 404,
        data: Data(#"{"error":"Audiobooks could not be found"}"#.utf8)
    )

    private func makeSUT(
        _ handler: @escaping (NetworkRequestProtocol) throws -> MockNetworkProvider.Reply
    ) -> (LibriVoxClient, MockNetworkProvider) {
        let network = MockNetworkProvider(handler: handler)
        return (LibriVoxClient(network: network), network)
    }

    private func searchReply() throws -> MockNetworkProvider.Reply {
        .init(data: try TestFixtures.librivoxData("search_alice"))
    }

    private func authorReply() -> MockNetworkProvider.Reply {
        let json = """
        {"books":[
        {"id":"900","title":"Author Hit Duplicate","url_iarchive":"https://archive.org/details/dup","language":"English",
         "totaltimesecs":60,"authors":[],"sections":[{"title":"One","listen_url":"https://archive.org/download/dup/a.mp3","playtime":"60"}]},
        {"id":"5000","title":"Only By Author","url_iarchive":"https://archive.org/details/only","language":"English",
         "totaltimesecs":60,"authors":[{"first_name":"Lewis","last_name":"Carroll"}],
         "sections":[{"title":"One","listen_url":"https://archive.org/download/only/a.mp3","playtime":"60"}]}]}
        """
        return .init(data: Data(json.utf8))
    }

    func test_search_sendsTitlePrefixAndAuthorRequests_withExtended() async throws {
        let reply = try searchReply()
        let (sut, network) = makeSUT { _ in reply }

        _ = try await sut.search("alice")

        let queries = network.requests.compactMap(\.queryParams)
        XCTAssertEqual(queries.count, 2)
        XCTAssertTrue(queries.contains { $0["title"] == "^alice" })
        XCTAssertTrue(queries.contains { $0["author"] == "alice" })
        XCTAssertTrue(queries.allSatisfy { $0["format"] == "json" && $0["extended"] == "1" })
        XCTAssertTrue(network.requests.allSatisfy { $0.endpoint == "https://librivox.org/api/feed/audiobooks/" })
    }

    func test_search_stripsLeadingArticle() async throws {
        let (sut, network) = makeSUT { _ in self.notFound }

        _ = try await sut.search("The Time Machine")

        let titles = network.requests.compactMap { $0.queryParams?["title"] }
        XCTAssertEqual(titles, ["^Time Machine"])
    }

    func test_search_mergesTitleAndAuthorResults() async throws {
        let title = try searchReply()
        let author = authorReply()
        let (sut, _) = makeSUT { request in
            request.queryParams?["title"] != nil ? title : author
        }

        let books = try await sut.search("alice")

        XCTAssertEqual(books.map(\.id), ["200", "900", "1122", "5000"])
        XCTAssertEqual(books.filter { $0.id == "900" }.count, 1)
        XCTAssertEqual(books.first { $0.id == "900" }?.title, "Alice's Adventures in Wonderland (version 3)")
    }

    func test_search_notFound404_returnsEmpty() async throws {
        let (sut, _) = makeSUT { _ in self.notFound }

        let books = try await sut.search("zzzqq")

        XCTAssertEqual(books, [])
    }

    func test_search_notFoundFixture_returnsEmpty() async throws {
        let body = try TestFixtures.librivoxData("not_found")
        let (sut, _) = makeSUT { _ in .init(statusCode: 404, data: body) }

        let books = try await sut.search("zzzqq")

        XCTAssertEqual(books, [])
    }

    func test_search_serverError_throws() async {
        let (sut, _) = makeSUT { _ in .init(statusCode: 500, data: Data("oops".utf8)) }

        do {
            _ = try await sut.search("alice")
            XCTFail("Expected an error")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func test_search_dropsBooksWithoutArchiveOrListenURLs() async throws {
        let reply = try searchReply()
        let (sut, _) = makeSUT { _ in reply }

        let books = try await sut.search("alice")

        XCTAssertFalse(books.contains { $0.id == "9001" })
        XCTAssertFalse(books.contains { $0.id == "9002" })
        XCTAssertEqual(books.map(\.id), ["200", "900", "1122"])
    }

    func test_search_blankQuery_returnsEmptyWithoutRequest() async throws {
        let (sut, network) = makeSUT { _ in self.notFound }

        let books = try await sut.search("   ")

        XCTAssertEqual(books, [])
        XCTAssertTrue(network.requests.isEmpty)
    }

    func test_search_mapsBookFields() async throws {
        let reply = try searchReply()
        let (sut, _) = makeSUT { _ in reply }

        let results = try await sut.search("alice")
        let alice = try XCTUnwrap(results.first)

        XCTAssertEqual(alice.id, "200")
        XCTAssertEqual(alice.authors, "Lewis Carroll")
        XCTAssertEqual(alice.archiveIdentifier, "alice_in_wonderland_librivox")
        XCTAssertEqual(alice.coverURL.absoluteString, "https://archive.org/services/img/alice_in_wonderland_librivox")
        XCTAssertEqual(alice.totalSeconds, 10_731)
        XCTAssertEqual(alice.sections.count, 12)
        XCTAssertEqual(alice.sections[0].seconds, 640)
    }

    func test_popular_requestsEachIDInOrder_andKeepsOrder() async throws {
        let reply = try searchReply()
        let (sut, network) = makeSUT { request in
            // Every id answers with the Alice fixture; the id only matters for the recorded request.
            _ = request
            return reply
        }

        let books = try await sut.popular()

        let ids = network.requests.compactMap { $0.queryParams?["id"] }
        XCTAssertEqual(Set(ids), ["200", "119", "253", "314", "448", "753", "271", "816", "56", "1557", "59"])
        XCTAssertEqual(ids.count, 11)
        XCTAssertTrue(network.requests.allSatisfy { $0.queryParams?["extended"] == "1" })
        XCTAssertFalse(books.isEmpty)
    }

    func test_popular_skipsNotFoundIDs() async throws {
        let reply = try searchReply()
        let (sut, _) = makeSUT { request in
            request.queryParams?["id"] == "200" ? reply : self.notFound
        }

        let books = try await sut.popular()

        XCTAssertEqual(books.map(\.id), ["200", "900", "1122"])
    }

    func test_details_sumsSectionSizesFromArchiveMetadata() async throws {
        let search = try searchReply()
        let metadata = MockNetworkProvider.Reply(data: try TestFixtures.librivoxData("archive_alice_metadata"))
        let (sut, network) = makeSUT { request in
            request.endpoint.contains("archive.org/metadata") ? metadata : search
        }
        let results = try await sut.search("alice")
        let alice = try XCTUnwrap(results.first)

        let details = try await sut.details(for: alice)

        XCTAssertEqual(details.totalBytes, 85_862_932)
        XCTAssertEqual(details.sectionBytes.count, 12)
        XCTAssertEqual(
            network.requests.last?.endpoint,
            "https://archive.org/metadata/alice_in_wonderland_librivox"
        )
    }

    func test_details_missingSizeCountsAsZero() async throws {
        let search = try searchReply()
        let json = #"{"files":[{"name":"wonderland_ch_01_64kb.mp3","size":"10"}]}"#
        let metadata = MockNetworkProvider.Reply(data: Data(json.utf8))
        let (sut, _) = makeSUT { request in
            request.endpoint.contains("archive.org/metadata") ? metadata : search
        }
        let results = try await sut.search("alice")
        let alice = try XCTUnwrap(results.first)

        let details = try await sut.details(for: alice)

        XCTAssertEqual(details.sectionBytes.first, 10)
        XCTAssertEqual(details.sectionBytes.dropFirst().reduce(0, +), 0)
        XCTAssertEqual(details.sectionBytes.count, 12)
    }

    func test_coverData_returnsBytesOnSuccess_andNilOnFailure() async throws {
        let search = try searchReply()
        let cover = Data([1, 2, 3])
        var succeed = true
        let (sut, _) = makeSUT { request in
            if request.endpoint.contains("services/img") {
                return succeed ? .init(data: cover) : .init(statusCode: 404, data: Data())
            }
            return search
        }
        let results = try await sut.search("alice")
        let alice = try XCTUnwrap(results.first)

        let ok = await sut.coverData(for: alice)
        succeed = false
        let failed = await sut.coverData(for: alice)

        XCTAssertEqual(ok, cover)
        XCTAssertNil(failed)
    }
}
