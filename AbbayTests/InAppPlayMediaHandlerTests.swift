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
    /// The handler's App Group store, fresh per test.
    private let appGroup = InMemoryKeyValueStore()

    private func makeHandler(
        router: IntentRouterProtocol = StubIntentRouter(),
        snapshotReader: @escaping () -> [LibrarySnapshotEntry]
    ) -> InAppPlayMediaHandler {
        InAppPlayMediaHandler(
            router: router,
            snapshotReader: snapshotReader,
            lastPlayed: .inMemory(appGroup),
            diagnostics: SiriDiagnostics(store: appGroup)
        )
    }

    private func intent(mediaName: String?, artistName: String? = nil) -> INPlayMediaIntent {
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
                    artistName: artistName,
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

    /// SiriKit can carry the author alone: "play something by Tolkien" (#207).
    func test_pick_artistOnly_picksTheirBook() throws {
        let entries = library() + [
            LibrarySnapshotEntry(title: "Silmarillion", urlString: "file:///silm", bookmarkData: nil, artist: "J. R. R. Tolkien")
        ]
        let handler = makeHandler(snapshotReader: { entries })
        let item = try XCTUnwrap(handler.pick(for: intent(mediaName: "", artistName: "Tolkien")))
        XCTAssertEqual(item.identifier, "file:///silm")
        XCTAssertNil(handler.pick(for: intent(mediaName: "", artistName: "Ursula Le Guin")))
    }

    func test_pick_matchesSpokenTitle() throws {
        let handler = makeHandler(snapshotReader: library)
        let item = try XCTUnwrap(handler.pick(for: intent(mediaName: "goblet of fire")))
        XCTAssertEqual(item.identifier, "file:///gof")
    }

    func test_pick_titlelessRequest_usesLastPlayed() throws {
        LastPlayedStore.inMemory(appGroup).save(url: try XCTUnwrap(URL(string: "file:///hobbit")))
        let handler = makeHandler(snapshotReader: library)
        let item = try XCTUnwrap(handler.pick(for: intent(mediaName: nil)))
        XCTAssertEqual(item.identifier, "file:///hobbit")
    }

    func test_pick_unknownTitle_returnsNil() {
        let handler = makeHandler(snapshotReader: library)
        XCTAssertNil(handler.pick(for: intent(mediaName: "Dune")))
    }

    func test_pick_emptyLibrary_returnsNil() {
        let handler = makeHandler(snapshotReader: { [] })
        XCTAssertNil(handler.pick(for: intent(mediaName: "anything")))
    }

    func test_resolveMediaItems_alwaysCompletesWithOneResult() {
        let handler = makeHandler(snapshotReader: library)
        let done = expectation(description: "resolve")
        handler.resolveMediaItems(for: intent(mediaName: "goblet of fire")) { results in
            XCTAssertEqual(results.count, 1)
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
    }

    func test_confirm_reportsReady() {
        let handler = makeHandler(snapshotReader: library)
        let done = expectation(description: "confirm")
        handler.confirm(intent: intent(mediaName: "goblet of fire")) { response in
            XCTAssertEqual(response.code, .ready)
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
    }

    func test_handle_delegatesToRouterAndReturnsItsResponse() {
        let router = StubIntentRouter()
        let handler = makeHandler(router: router, snapshotReader: library)
        let done = expectation(description: "handle")
        handler.handle(intent: intent(mediaName: "goblet of fire")) { response in
            XCTAssertEqual(response.code, .success)
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(router.handled, 1)
    }
}
