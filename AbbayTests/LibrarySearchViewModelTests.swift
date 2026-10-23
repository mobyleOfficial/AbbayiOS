//
//  LibrarySearchViewModelTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

@MainActor
final class LibrarySearchViewModelTests: XCTestCase {
    private let client = MockLibriVoxClient()
    private let path = FakeNetworkPath()

    private func makeSUT(library: [AudioModel] = []) -> LibrarySearchViewModel {
        let sut = LibrarySearchViewModel(client: client, path: path, debounce: .milliseconds(30))
        sut.update(library: library)
        return sut
    }

    private func audio(_ title: String, artist: String = "", librivoxID: String? = nil) -> AudioModel {
        AudioModel(title: title, artist: artist, url: URL(string: "file:///\(title)"), librivoxID: librivoxID)
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

    func test_query_filtersLocalByTitleAndArtist_caseInsensitive() {
        let sut = makeSUT(library: [
            audio("Émile et les détectives"),
            audio("Moby Dick", artist: "Herman Melville"),
            audio("Other", artist: "Someone")
        ])

        sut.query = "EMILE"
        XCTAssertEqual(sut.localResults.map(\.title), ["Émile et les détectives"])

        sut.query = "melville"
        XCTAssertEqual(sut.localResults.map(\.title), ["Moby Dick"])
    }

    func test_query_debouncesRemoteSearch() async {
        let sut = makeSUT()
        client.searchResult = .success([book("1")])

        sut.query = "al"
        sut.query = "alice"
        await waitUntil { sut.remoteStatus == .loaded }

        XCTAssertEqual(client.searchQueries, ["alice"])
        XCTAssertEqual(sut.remoteResults.map(\.id), ["1"])
    }

    func test_remote_excludesBooksAlreadyInLibrary() async {
        let sut = makeSUT(library: [audio("Mine", librivoxID: "1")])
        client.searchResult = .success([book("1"), book("2")])

        sut.query = "book"
        await waitUntil { sut.remoteStatus == .loaded }

        XCTAssertEqual(sut.remoteResults.map(\.id), ["2"])
    }

    func test_offline_setsOfflineWithoutRequest() async {
        path.isOnline = false
        let sut = makeSUT()

        sut.query = "alice"
        await waitUntil { sut.remoteStatus == .offline }
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(sut.remoteStatus, .offline)
        XCTAssertTrue(client.searchQueries.isEmpty)
    }

    func test_failure_setsFailed() async {
        let sut = makeSUT()
        client.searchResult = .failure(URLError(.badServerResponse))

        sut.query = "alice"
        await waitUntil { sut.remoteStatus == .failed }

        XCTAssertEqual(sut.remoteStatus, .failed)
        XCTAssertTrue(sut.remoteResults.isEmpty)
    }

    func test_emptyQuery_clearsResults() async {
        let sut = makeSUT(library: [audio("Alice")])
        client.searchResult = .success([book("2")])
        sut.query = "alice"
        await waitUntil { sut.remoteStatus == .loaded }

        sut.query = ""

        XCTAssertTrue(sut.localResults.isEmpty)
        XCTAssertTrue(sut.remoteResults.isEmpty)
        XCTAssertEqual(sut.remoteStatus, .idle)
    }

    func test_loadPopular_setsRemoteResults() async {
        let sut = makeSUT()
        client.popularResult = .success([book("7")])

        await sut.loadPopular()

        XCTAssertEqual(client.popularCalls, 1)
        XCTAssertEqual(sut.remoteResults.map(\.id), ["7"])
        XCTAssertEqual(sut.remoteStatus, .loaded)
    }

    func test_loadPopular_offline_noCache_setsOffline() async {
        path.isOnline = false
        let sut = makeSUT()
        client.popularResult = .failure(URLError(.notConnectedToInternet))

        await sut.loadPopular()

        XCTAssertEqual(sut.remoteStatus, .offline)
        XCTAssertEqual(client.popularCalls, 1)
        XCTAssertTrue(sut.remoteResults.isEmpty)
    }

    func test_loadPopular_offline_emptyList_setsOffline() async {
        path.isOnline = false
        let sut = makeSUT()
        client.popularResult = .success([])

        await sut.loadPopular()

        XCTAssertEqual(sut.remoteStatus, .offline)
    }

    /// The client answers from its cache without the network.
    func test_loadPopular_offline_withCachedPopular_showsIt() async {
        path.isOnline = false
        let sut = makeSUT()
        client.popularResult = .success([book("7")])

        await sut.loadPopular()

        XCTAssertEqual(sut.remoteStatus, .loaded)
        XCTAssertEqual(sut.remoteResults.map(\.id), ["7"])
    }

    func test_clearingQuery_afterBrowsing_restoresPopular() async {
        let sut = makeSUT()
        client.popularResult = .success([book("7")])
        client.searchResult = .success([book("9")])
        await sut.loadPopular()
        sut.query = "alice"
        await waitUntil { sut.remoteResults.map(\.id) == ["9"] }

        sut.query = ""

        XCTAssertEqual(sut.remoteResults.map(\.id), ["7"])
        XCTAssertEqual(sut.remoteStatus, .loaded)
    }

    func test_updateLibrary_removesNewlyOwnedBookFromRemote() async {
        let sut = makeSUT()
        client.popularResult = .success([book("1"), book("2")])
        await sut.loadPopular()

        sut.update(library: [audio("Mine", librivoxID: "1")])

        XCTAssertEqual(sut.remoteResults.map(\.id), ["2"])
    }
}
