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
    private var flagSuite: UserDefaults?
    private var flagSuiteName: String?

    override func setUpWithError() throws {
        try super.setUpWithError()
        loadAudio = MockLoadAudioUseCase()
        snapshotWriter = MockLibrarySnapshotWriter()
        playerMock = MockPlayer()
        let name = "test.flag.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        suite.removePersistentDomain(forName: name)
        flagSuiteName = name
        flagSuite = suite
        LaunchStateFlag.defaults = suite
    }

    override func tearDownWithError() throws {
        if let name = flagSuiteName, let suite = flagSuite {
            suite.removePersistentDomain(forName: name)
        }
        LaunchStateFlag.defaults = AppGroup.defaults
        try super.tearDownWithError()
    }

    private func makeIntent(identifier: String) -> INPlayMediaIntent {
        let item = INMediaItem(identifier: identifier, title: "X", type: .audioBook, artwork: nil)
        return INPlayMediaIntent(
            mediaItems: [item], mediaContainer: nil, playShuffled: nil,
            playbackRepeatMode: .none, resumePlayback: nil,
            playbackQueueLocation: .now, playbackSpeed: nil, mediaSearch: nil
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
            player: { mock }
        )
    }

    func test_handle_audioUnavailable_returnsFailure_doesNotCallPlayer() throws {
        LaunchStateFlag.markUnavailable()
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
        let storeSuiteName = "test.store.\(UUID().uuidString)"
        let storeSuite = try XCTUnwrap(UserDefaults(suiteName: storeSuiteName))
        let originalDefaults = LastPlayedStore.defaults
        LastPlayedStore.defaults = storeSuite
        defer {
            storeSuite.removePersistentDomain(forName: storeSuiteName)
            LastPlayedStore.defaults = originalDefaults
        }
        storeSuite.set("file:///gone", forKey: LastPlayedStore.key)

        let router = try makeRouter()
        _ = router.handle(makeIntent(identifier: "file:///gone"))
        XCTAssertNil(storeSuite.string(forKey: LastPlayedStore.key))
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
}
