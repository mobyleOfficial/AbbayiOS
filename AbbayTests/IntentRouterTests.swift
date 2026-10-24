//
//  IntentRouterTests.swift
//  AbbayTests
//

@testable import Abbay
import AVFoundation
import Combine
import Intents
import XCTest

final class IntentRouterTests: XCTestCase {
    private var loadAudio: MockLoadAudioUseCase?
    private var snapshotWriter: MockLibrarySnapshotWriter?
    private var playerMock: MockPlayer?
    /// The router's App Group store, fresh per test.
    private let appGroup = InMemoryKeyValueStore()

    override func setUpWithError() throws {
        try super.setUpWithError()
        loadAudio = MockLoadAudioUseCase()
        snapshotWriter = MockLibrarySnapshotWriter()
        playerMock = MockPlayer()
    }

    private func makeIntent(identifier: String) -> INPlayMediaIntent {
        let item = INMediaItem(identifier: identifier, title: "X", type: .audioBook, artwork: nil)
        return INPlayMediaIntent(
            mediaItems: [item],
            mediaContainer: nil,
            playShuffled: nil,
            playbackRepeatMode: .none,
            resumePlayback: nil,
            playbackQueueLocation: .now,
            playbackSpeed: nil,
            mediaSearch: nil
        )
    }

    private static func search(for name: String) -> INMediaSearch {
        INMediaSearch(
            mediaType: .audioBook,
            sortOrder: .unknown,
            mediaName: name,
            artistName: nil,
            albumName: nil,
            genreNames: nil,
            moodNames: nil,
            releaseDate: nil,
            reference: .unknown,
            mediaIdentifier: nil
        )
    }

    /// The in-app dispatch path: iOS hands `INPlayMediaIntent` straight to the app
    /// with nothing resolved, so only `mediaSearch` is populated.
    private func makeUnresolvedIntent(mediaName: String?) -> INPlayMediaIntent {
        INPlayMediaIntent(
            mediaItems: nil,
            mediaContainer: nil,
            playShuffled: nil,
            playbackRepeatMode: .none,
            resumePlayback: nil,
            playbackQueueLocation: .now,
            playbackSpeed: nil,
            mediaSearch: mediaName.map(Self.search(for:))
        )
    }

    private func makeRouter(snapshotEntries: [LibrarySnapshotEntry] = []) throws -> IntentRouter {
        let loader = try XCTUnwrap(loadAudio)
        let writer = try XCTUnwrap(snapshotWriter)
        let mock = try XCTUnwrap(playerMock)
        return IntentRouter(
            loadAudio: loader,
            snapshotWriter: writer,
            snapshotReader: { snapshotEntries },
            player: { mock },
            lastPlayed: .inMemory(appGroup),
            launchState: .inMemory(appGroup)
        )
    }

    func test_handle_audioUnavailable_returnsFailure_doesNotCallPlayer() throws {
        LaunchStateFlag.inMemory(appGroup).markUnavailable()
        let router = try makeRouter()
        let response = router.handle(makeIntent(identifier: "file:///x"))
        XCTAssertEqual(response.code, .failureUnknownMediaType)
        let loader = try XCTUnwrap(loadAudio)
        let mock = try XCTUnwrap(playerMock)
        XCTAssertEqual(loader.executeCalls.count, 0)
        XCTAssertTrue(mock.playCalls.isEmpty)
    }

    func test_handle_loadAudioReturnsNil_returnsFailure_refreshesSnapshot() throws {
        let router = try makeRouter()
        let response = router.handle(makeIntent(identifier: "file:///gone"))
        XCTAssertEqual(response.code, .failureUnknownMediaType)
        let writer = try XCTUnwrap(snapshotWriter)
        XCTAssertEqual(writer.refreshCallCount, 1)
    }

    func test_handle_loadAudioReturnsNil_matchedLastPlayed_clearsLastPlayed() throws {
        appGroup.set("file:///gone", forKey: LastPlayedStore.key)

        let router = try makeRouter()
        _ = router.handle(makeIntent(identifier: "file:///gone"))
        XCTAssertNil(appGroup.object(forKey: LastPlayedStore.key))
    }

    func test_handle_snapshotBookmarkPresent_resolvesViaBookmark() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data().write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let bookmark = try tempURL.bookmarkData(options: .minimalBookmark)
        let identifier = tempURL.absoluteString
        let entry = LibrarySnapshotEntry(title: "T", urlString: identifier, bookmarkData: bookmark)
        let loader = try XCTUnwrap(loadAudio)
        loader.stubs[tempURL.absoluteString] = AudioModel(url: tempURL)

        let router = try makeRouter(snapshotEntries: [entry])
        _ = router.handle(makeIntent(identifier: identifier))

        XCTAssertEqual(loader.executeCalls.last as? URL, tempURL)
    }

    func test_handle_validIntent_callsPlayer_returnsSuccess() throws {
        let url = try XCTUnwrap(URL(string: "file:///book.m4a"))
        let loader = try XCTUnwrap(loadAudio)
        loader.stubs[url.absoluteString] = AudioModel(url: url)
        let router = try makeRouter()
        let response = router.handle(makeIntent(identifier: url.absoluteString))
        XCTAssertEqual(response.code, .success)
        let mock = try XCTUnwrap(playerMock)
        XCTAssertEqual(mock.playCalls.count, 1)
    }

    // MARK: - In-app dispatch (no resolved media items)

    func test_handle_unresolvedIntent_matchesSpokenTitleFromSnapshot() throws {
        let url = try XCTUnwrap(URL(string: "file:///gof"))
        var book = AudioModel()
        book.title = "Harry Potter and the Goblet of Fire"
        book.url = url
        try XCTUnwrap(loadAudio).stubs[url.absoluteString] = book

        let router = try makeRouter(snapshotEntries: [
            LibrarySnapshotEntry(
                title: "Harry Potter and the Goblet of Fire",
                urlString: url.absoluteString,
                bookmarkData: nil
            ),
            LibrarySnapshotEntry(title: "The Hobbit", urlString: "file:///hobbit", bookmarkData: nil)
        ])
        let response = router.handle(makeUnresolvedIntent(mediaName: "goblet of fire"))

        XCTAssertEqual(response.code, .success)
        XCTAssertEqual(
            try XCTUnwrap(playerMock).playCalls.map(\.title),
            ["Harry Potter and the Goblet of Fire"]
        )
    }

    func test_handle_unresolvedIntent_noMediaSearch_resumesLastPlayed() throws {
        let url = try XCTUnwrap(URL(string: "file:///ootp"))
        var book = AudioModel()
        book.title = "Order of the Phoenix"
        book.url = url
        try XCTUnwrap(loadAudio).stubs[url.absoluteString] = book

        let router = try makeRouter(snapshotEntries: [
            LibrarySnapshotEntry(
                title: "Order of the Phoenix",
                urlString: url.absoluteString,
                bookmarkData: nil
            )
        ])
        let response = router.handle(makeUnresolvedIntent(mediaName: nil))

        XCTAssertEqual(response.code, .success)
        XCTAssertEqual(try XCTUnwrap(playerMock).playCalls.count, 1)
    }

    func test_handle_unresolvedIntent_emptyLibrary_reportsFailure() throws {
        let router = try makeRouter(snapshotEntries: [])
        let response = router.handle(makeUnresolvedIntent(mediaName: "anything"))

        XCTAssertEqual(response.code, .failureUnknownMediaType)
        XCTAssertTrue(try XCTUnwrap(playerMock).playCalls.isEmpty)
    }

    func test_handle_unresolvedIntent_unknownTitle_reportsFailure() throws {
        let router = try makeRouter(snapshotEntries: [
            LibrarySnapshotEntry(title: "The Hobbit", urlString: "file:///hobbit", bookmarkData: nil)
        ])
        let response = router.handle(makeUnresolvedIntent(mediaName: "Dune"))

        XCTAssertEqual(response.code, .failureUnknownMediaType)
        XCTAssertTrue(try XCTUnwrap(playerMock).playCalls.isEmpty)
    }
}
