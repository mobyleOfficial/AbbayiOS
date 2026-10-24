//
//  LibriVoxSearchViewModelTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

@MainActor
final class LibriVoxSearchViewModelTests: XCTestCase {
    private let client = MockLibriVoxClient()
    private let path = FakeNetworkPath()

    private func makeSUT() -> LibriVoxSearchViewModel {
        LibriVoxSearchViewModel(client: client, path: path, debounce: .milliseconds(30))
    }

    private func book(_ id: String, title: String = "Book") -> LibriVoxBook {
        LibriVoxBook(
            id: id,
            title: title,
            authors: "Author",
            descriptionText: "",
            language: "English",
            totalSeconds: 60,
            coverURL: URL(fileURLWithPath: "/cover"),
            sections: []
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func test_query_debouncesRemoteSearch() async {
        let sut = makeSUT()
        client.searchResult = .success([book("1")])

        sut.query = "al"
        sut.query = "alice"
        await waitUntil { sut.status == .loaded }

        XCTAssertEqual(client.searchQueries, ["alice"])
        XCTAssertEqual(sut.results.map(\.id), ["1"])
    }

    func test_blankQuery_makesNoRequest() async {
        let sut = makeSUT()

        sut.query = "   "
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(client.searchQueries.isEmpty)
        XCTAssertEqual(sut.status, .idle)
    }

    func test_ownedBooks_areNotExcluded() async {
        let sut = makeSUT()
        client.searchResult = .success([book("1"), book("2")])

        sut.query = "book"
        await waitUntil { sut.status == .loaded }

        XCTAssertEqual(sut.results.map(\.id), ["1", "2"])
    }

    func test_offline_setsOfflineWithoutRequest() async {
        path.isOnline = false
        let sut = makeSUT()

        sut.query = "alice"
        await waitUntil { sut.status == .offline }
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(sut.status, .offline)
        XCTAssertTrue(client.searchQueries.isEmpty)
    }

    func test_failure_setsFailed() async {
        let sut = makeSUT()
        client.searchResult = .failure(URLError(.badServerResponse))

        sut.query = "alice"
        await waitUntil { sut.status == .failed }

        XCTAssertEqual(sut.status, .failed)
        XCTAssertTrue(sut.results.isEmpty)
    }

    func test_staleSearchResponse_arrivingLast_isIgnored() async {
        let gated = GatedLibriVoxClient()
        let sut = LibriVoxSearchViewModel(client: gated, path: path, debounce: .milliseconds(1))
        sut.query = "a"
        await waitUntil { gated.pendingSearches.count == 1 }
        sut.query = "b"
        await waitUntil { gated.pendingSearches.count == 2 }

        gated.release(search: "b", with: [book("B")])
        await waitUntil { sut.status == .loaded }
        gated.release(search: "a", with: [book("A")])
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(sut.results.map(\.id), ["B"])
        XCTAssertEqual(sut.status, .loaded)
    }

    func test_staleSearchResponse_afterQueryCleared_isIgnored() async {
        let gated = GatedLibriVoxClient()
        let sut = LibriVoxSearchViewModel(client: gated, path: path, debounce: .milliseconds(1))
        sut.query = "a"
        await waitUntil { gated.pendingSearches.count == 1 }
        sut.query = ""

        gated.release(search: "a", with: [book("A")])
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(sut.results.isEmpty)
        XCTAssertNotEqual(sut.status, .failed)
    }

    func test_typingAndClearing_whilePopularLoads_stillShowsPopular() async {
        let gated = GatedLibriVoxClient()
        let sut = LibriVoxSearchViewModel(client: gated, path: path, debounce: .milliseconds(1))
        let load = Task { await sut.loadPopular() }
        await waitUntil { gated.popularPending }

        sut.query = "alice"
        sut.query = ""
        XCTAssertEqual(sut.status, .loading)
        gated.releasePopular(with: [book("7")])
        await load.value

        XCTAssertEqual(sut.popular.map(\.id), ["7"])
        XCTAssertEqual(sut.status, .loaded)
    }

    func test_popularResponse_whileSearching_doesNotOverrideSearchStatus() async {
        let gated = GatedLibriVoxClient()
        let sut = LibriVoxSearchViewModel(client: gated, path: path, debounce: .milliseconds(1))
        let load = Task { await sut.loadPopular() }
        await waitUntil { gated.popularPending }
        sut.query = "alice"
        await waitUntil { gated.pendingSearches.count == 1 }

        gated.releasePopular(with: [book("7")])
        await load.value

        XCTAssertEqual(sut.popular.map(\.id), ["7"])
        XCTAssertEqual(sut.status, .loading)
        gated.release(search: "alice", with: [book("A")])
        await waitUntil { sut.status == .loaded }
        XCTAssertEqual(sut.results.map(\.id), ["A"])
    }

    func test_reloadingPopular_whenAlreadyLoaded_neverShowsLoading() async {
        let sut = makeSUT()
        client.popularResult = .success([book("7")])
        await sut.loadPopular()
        var sawLoading = false
        func track() {
            withObservationTracking {
                if sut.status == .loading { sawLoading = true }
            } onChange: {
                Task { @MainActor in
                    if sut.status == .loading { sawLoading = true }
                    track()
                }
            }
        }
        track()
        client.popularResult = .success([book("7"), book("8")])

        await sut.loadPopular()
        await Task.yield()

        XCTAssertFalse(sawLoading)
        XCTAssertEqual(sut.status, .loaded)
        XCTAssertEqual(sut.popular.map(\.id), ["7", "8"])
    }

    func test_reloadingPopular_failure_keepsShownList() async {
        let sut = makeSUT()
        client.popularResult = .success([book("7")])
        await sut.loadPopular()
        client.popularResult = .failure(URLError(.badServerResponse))

        await sut.loadPopular()

        XCTAssertEqual(sut.popular.map(\.id), ["7"])
        XCTAssertEqual(sut.status, .loaded)
    }

    func test_emptyQuery_clearsResults() async {
        let sut = makeSUT()
        client.searchResult = .success([book("2")])
        sut.query = "alice"
        await waitUntil { sut.status == .loaded }

        sut.query = ""

        XCTAssertTrue(sut.results.isEmpty)
        XCTAssertEqual(sut.status, .idle)
    }

    func test_loadPopular_setsPopular() async {
        let sut = makeSUT()
        client.popularResult = .success([book("7")])

        await sut.loadPopular()

        XCTAssertEqual(client.popularCalls, 1)
        XCTAssertEqual(sut.popular.map(\.id), ["7"])
        XCTAssertTrue(sut.results.isEmpty)
        XCTAssertEqual(sut.status, .loaded)
    }

    func test_loadPopular_offline_noCache_setsOffline() async {
        path.isOnline = false
        let sut = makeSUT()
        client.popularResult = .failure(URLError(.notConnectedToInternet))

        await sut.loadPopular()

        XCTAssertEqual(sut.status, .offline)
        XCTAssertEqual(client.popularCalls, 1)
        XCTAssertTrue(sut.popular.isEmpty)
    }

    func test_loadPopular_offline_emptyList_setsOffline() async {
        path.isOnline = false
        let sut = makeSUT()
        client.popularResult = .success([])

        await sut.loadPopular()

        XCTAssertEqual(sut.status, .offline)
    }

    /// The client answers from its cache without the network.
    func test_loadPopular_offline_withCachedPopular_showsIt() async {
        path.isOnline = false
        let sut = makeSUT()
        client.popularResult = .success([book("7")])

        await sut.loadPopular()

        XCTAssertEqual(sut.status, .loaded)
        XCTAssertEqual(sut.popular.map(\.id), ["7"])
    }

    func test_clearingQuery_afterBrowsing_restoresPopular() async {
        let sut = makeSUT()
        client.popularResult = .success([book("7")])
        client.searchResult = .success([book("9")])
        await sut.loadPopular()
        sut.query = "alice"
        await waitUntil { sut.results.map(\.id) == ["9"] }

        sut.query = ""

        XCTAssertTrue(sut.results.isEmpty)
        XCTAssertEqual(sut.popular.map(\.id), ["7"])
        XCTAssertEqual(sut.status, .loaded)
    }
}

/// A client whose requests suspend until the test releases them.
@MainActor
private final class GatedLibriVoxClient: LibriVoxClientProtocol {
    private(set) var pendingSearches: [String] = []
    private var searchContinuations: [String: CheckedContinuation<[LibriVoxBook], Never>] = [:]
    private var popularContinuation: CheckedContinuation<[LibriVoxBook], Never>?
    var popularPending: Bool { popularContinuation != nil }

    func search(_ query: String) async throws -> [LibriVoxBook] {
        await withCheckedContinuation { continuation in
            pendingSearches.append(query)
            searchContinuations[query] = continuation
        }
    }

    func popular() async throws -> [LibriVoxBook] {
        await withCheckedContinuation { popularContinuation = $0 }
    }

    func details(for book: LibriVoxBook) async throws -> LibriVoxBookDetails {
        throw URLError(.unsupportedURL)
    }

    func coverData(for book: LibriVoxBook) async -> Data? { nil }

    func release(search query: String, with books: [LibriVoxBook]) {
        searchContinuations.removeValue(forKey: query)?.resume(returning: books)
    }

    func releasePopular(with books: [LibriVoxBook]) {
        popularContinuation?.resume(returning: books)
        popularContinuation = nil
    }
}
