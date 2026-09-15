//
//  InAppPlayMediaHandlerTests.swift
//  AbbayTests
//

@testable import Abbay
import Intents
import XCTest

private final class StubIntentRouter: IntentRouterProtocol {
    var handled = 0
    var response = INPlayMediaIntentResponse(code: .success, userActivity: nil)

    func handle(_ intent: INPlayMediaIntent) -> INPlayMediaIntentResponse {
        handled += 1
        return response
    }
}

final class InAppPlayMediaHandlerTests: XCTestCase {
    private let suiteName = "abbay.tests.InAppPlayMediaHandlerTests"

    override func setUpWithError() throws {
        try super.setUpWithError()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        LastPlayedStore.defaults = defaults
        LastPlayedStore.standardFallback = defaults
        SiriDiagnostics.defaults = defaults
    }

    override func tearDownWithError() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        LastPlayedStore.defaults = AppGroup.defaults
        LastPlayedStore.standardFallback = .standard
        SiriDiagnostics.defaults = AppGroup.defaults
        try super.tearDownWithError()
    }

    private func intent(mediaName: String?) -> INPlayMediaIntent {
        INPlayMediaIntent(
            mediaItems: nil,
            mediaContainer: nil,
            playShuffled: nil,
            playbackRepeatMode: .none,
            resumePlayback: nil,
            playbackQueueLocation: .now,
            playbackSpeed: nil,
            mediaSearch: mediaName.map { name in
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
        )
    }

    private func library() -> [LibrarySnapshotEntry] {
        [
            LibrarySnapshotEntry(
                title: "Harry Potter and the Goblet of Fire",
                urlString: "file:///gof",
                bookmarkData: nil
            ),
            LibrarySnapshotEntry(title: "The Hobbit", urlString: "file:///hobbit", bookmarkData: nil)
        ]
    }

    func test_pick_matchesSpokenTitle() throws {
        let handler = InAppPlayMediaHandler(router: StubIntentRouter(), snapshotReader: library)
        let item = try XCTUnwrap(handler.pick(for: intent(mediaName: "goblet of fire")))
        XCTAssertEqual(item.identifier, "file:///gof")
    }

    func test_pick_titlelessRequest_usesLastPlayed() throws {
        LastPlayedStore.save(url: try XCTUnwrap(URL(string: "file:///hobbit")))
        let handler = InAppPlayMediaHandler(router: StubIntentRouter(), snapshotReader: library)
        let item = try XCTUnwrap(handler.pick(for: intent(mediaName: nil)))
        XCTAssertEqual(item.identifier, "file:///hobbit")
    }

    func test_pick_unknownTitle_returnsNil() {
        let handler = InAppPlayMediaHandler(router: StubIntentRouter(), snapshotReader: library)
        XCTAssertNil(handler.pick(for: intent(mediaName: "Dune")))
    }

    func test_pick_emptyLibrary_returnsNil() {
        let handler = InAppPlayMediaHandler(router: StubIntentRouter(), snapshotReader: { [] })
        XCTAssertNil(handler.pick(for: intent(mediaName: "anything")))
    }

    func test_resolveMediaItems_alwaysCompletesWithOneResult() {
        let handler = InAppPlayMediaHandler(router: StubIntentRouter(), snapshotReader: library)
        let done = expectation(description: "resolve")
        handler.resolveMediaItems(for: intent(mediaName: "goblet of fire")) { results in
            XCTAssertEqual(results.count, 1)
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
    }

    func test_confirm_reportsReady() {
        let handler = InAppPlayMediaHandler(router: StubIntentRouter(), snapshotReader: library)
        let done = expectation(description: "confirm")
        handler.confirm(intent: intent(mediaName: "goblet of fire")) { response in
            XCTAssertEqual(response.code, .ready)
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
    }

    func test_handle_delegatesToRouterAndReturnsItsResponse() {
        let router = StubIntentRouter()
        let handler = InAppPlayMediaHandler(router: router, snapshotReader: library)
        let done = expectation(description: "handle")
        handler.handle(intent: intent(mediaName: "goblet of fire")) { response in
            XCTAssertEqual(response.code, .success)
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(router.handled, 1)
    }
}
