//
//  PlayMediaIntentHandlerTests.swift
//  AbbayIntentsTests
//

import Intents
import XCTest

// NOTE: AbbayIntents source files are compiled directly into this test bundle
// (see project.yml). We do NOT `@testable import AbbayIntents` because an
// app-extension binary cannot be linked into a unit-test bundle.

final class PlayMediaIntentHandlerTests: XCTestCase {
    /// The handler's App Group store, fresh per test (XCTest builds one instance per test).
    private let appGroup = InMemoryKeyValueStore()
    private var lastPlayed: LastPlayedStore {
        LastPlayedStore(store: appGroup, legacyStore: InMemoryKeyValueStore())
    }
    private var launchState: LaunchStateFlag { LaunchStateFlag(store: appGroup) }
    private var handler: PlayMediaIntentHandler?

    override func setUpWithError() throws {
        try super.setUpWithError()
        handler = PlayMediaIntentHandler(
            lastPlayed: lastPlayed,
            launchState: launchState,
            librarySnapshot: LibrarySnapshotReader(store: appGroup),
            diagnostics: SiriDiagnostics(store: appGroup)
        )
    }

    private func makeIntent(mediaName: String, mediaItems: [INMediaItem]? = nil) -> INPlayMediaIntent {
        INPlayMediaIntent(
            mediaItems: mediaItems, mediaContainer: nil, playShuffled: nil,
            playbackRepeatMode: .none, resumePlayback: nil,
            playbackQueueLocation: .now, playbackSpeed: nil,
            mediaSearch: INMediaSearch(
                mediaType: .audioBook, sortOrder: .unknown,
                mediaName: mediaName, artistName: nil, albumName: nil,
                genreNames: nil, moodNames: nil, releaseDate: nil,
                reference: .unknown, mediaIdentifier: nil
            )
        )
    }

    private func writeSnapshot(_ entries: [LibrarySnapshotEntry]) throws {
        let snapshot = LibrarySnapshot(version: 1, updatedAt: Date(), audios: entries)
        let data = try JSONEncoder().encode(snapshot)
        appGroup.set(data, forKey: LibrarySnapshotWriter.key)
    }

    // Tests target the internal `decide(for:)` method because the public
    // `resolveMediaItems` wraps results in opaque
    // `INPlayMediaMediaItemResolutionResult` values with no public accessors —
    // asserting `results.count == 1` on the wrapper is a tautology.

    func test_decide_singleMatch_returnsSingleMatchOutcome() throws {
        try writeSnapshot([
            LibrarySnapshotEntry(title: "Harry Potter", urlString: "file:///hp", bookmarkData: nil)
        ])
        let handler = try XCTUnwrap(self.handler)
        let outcome = handler.decide(for: makeIntent(mediaName: "Harry Potter"))

        guard case .singleMatch(let item) = outcome else {
            return XCTFail("expected .singleMatch, got \(outcome)")
        }
        XCTAssertEqual(item.title, "Harry Potter")
        XCTAssertEqual(item.identifier, "file:///hp")
    }

    func test_decide_twoMatchesAtTopScore_returnsDisambiguationOutcome() throws {
        try writeSnapshot([
            LibrarySnapshotEntry(title: "Harry Potter and the Sorcerer's Stone", urlString: "file:///a", bookmarkData: nil),
            LibrarySnapshotEntry(title: "Harry Potter and the Chamber of Secrets", urlString: "file:///b", bookmarkData: nil)
        ])
        let handler = try XCTUnwrap(self.handler)
        let outcome = handler.decide(for: makeIntent(mediaName: "Harry Potter"))

        guard case .disambiguation(let items) = outcome else {
            return XCTFail("expected .disambiguation, got \(outcome)")
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains { ($0.title ?? "").contains("Sorcerer") })
        XCTAssertTrue(items.contains { ($0.title ?? "").contains("Chamber") })
    }

    func test_decide_moreThanFiveAtTopScore_returnsFallbackBestOutcome() throws {
        let entries = (0..<6).map { idx in
            LibrarySnapshotEntry(
                title: "Audiobook \(idx)",
                urlString: "file:///book-\(idx)",
                bookmarkData: nil
            )
        }
        try writeSnapshot(entries)
        let handler = try XCTUnwrap(self.handler)
        let outcome = handler.decide(for: makeIntent(mediaName: "Audiobook"))

        guard case .fallbackBest(let item) = outcome else {
            return XCTFail("expected .fallbackBest (>5 cap), got \(outcome)")
        }
        // Tiebreak (no last-played): library-index ASC → first entry wins.
        XCTAssertEqual(item.identifier, "file:///book-0")
    }

    func test_decide_emptyLibrary_returnsEmptyLibraryOutcome() throws {
        let handler = try XCTUnwrap(self.handler)
        XCTAssertEqual(handler.decide(for: makeIntent(mediaName: "Anything")), .emptyLibrary)
    }

    func test_decide_noMatch_returnsNoMatchOutcome() throws {
        try writeSnapshot([
            LibrarySnapshotEntry(title: "Harry Potter", urlString: "file:///hp", bookmarkData: nil)
        ])
        let handler = try XCTUnwrap(self.handler)
        XCTAssertEqual(handler.decide(for: makeIntent(mediaName: "Star Wars")), .noMatch)
    }

    // MARK: Title-less requests ("play in Abbay" / "resume")

    func test_decide_emptyMediaName_withLastPlayed_resumesThatBook() throws {
        try writeSnapshot([
            LibrarySnapshotEntry(title: "Goblet of Fire", urlString: "file:///gof", bookmarkData: nil),
            LibrarySnapshotEntry(title: "Order of the Phoenix", urlString: "file:///ootp", bookmarkData: nil)
        ])
        lastPlayed.save(url: try XCTUnwrap(URL(string: "file:///ootp")))
        let handler = try XCTUnwrap(self.handler)
        guard case .singleMatch(let item) = handler.decide(for: makeIntent(mediaName: "")) else {
            return XCTFail("expected singleMatch for title-less request with a last-played book")
        }
        XCTAssertEqual(item.identifier, "file:///ootp")
    }

    func test_decide_emptyMediaName_withoutLastPlayed_usesFirstLibraryEntry() throws {
        try writeSnapshot([
            LibrarySnapshotEntry(title: "Goblet of Fire", urlString: "file:///gof", bookmarkData: nil),
            LibrarySnapshotEntry(title: "Order of the Phoenix", urlString: "file:///ootp", bookmarkData: nil)
        ])
        let handler = try XCTUnwrap(self.handler)
        guard case .singleMatch(let item) = handler.decide(for: makeIntent(mediaName: "")) else {
            return XCTFail("expected singleMatch for title-less request on a fresh library")
        }
        XCTAssertEqual(item.identifier, "file:///gof")
    }

    func test_decide_whitespaceOnlyMediaName_treatedAsTitleless() throws {
        try writeSnapshot([
            LibrarySnapshotEntry(title: "Goblet of Fire", urlString: "file:///gof", bookmarkData: nil)
        ])
        let handler = try XCTUnwrap(self.handler)
        guard case .singleMatch = handler.decide(for: makeIntent(mediaName: "   ")) else {
            return XCTFail("expected singleMatch for a whitespace-only media name")
        }
    }

    func test_decide_emptyMediaName_emptyLibrary_stillReportsEmptyLibrary() throws {
        let handler = try XCTUnwrap(self.handler)
        XCTAssertEqual(handler.decide(for: makeIntent(mediaName: "")), .emptyLibrary)
    }

    func test_decide_audioSessionUnavailableFlag_returnsUnavailableOutcome() throws {
        launchState.markUnavailable()
        let handler = try XCTUnwrap(self.handler)
        XCTAssertEqual(handler.decide(for: makeIntent(mediaName: "Anything")), .unavailable)
    }

    // Smoke test: ensure resolveMediaItems wraps the outcome and completes.
    // (Cannot inspect the wrapped resolution result via public API.)
    func test_resolveMediaItems_callsCompletion() throws {
        try writeSnapshot([
            LibrarySnapshotEntry(title: "Harry Potter", urlString: "file:///hp", bookmarkData: nil)
        ])
        let exp = expectation(description: "resolve")
        let handler = try XCTUnwrap(self.handler)
        handler.resolveMediaItems(for: makeIntent(mediaName: "Harry Potter")) { results in
            XCTAssertEqual(results.count, 1)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func test_handle_singleMatchPath_returnsHandleInApp() throws {
        let item = INMediaItem(identifier: "file:///hp", title: "Harry Potter", type: .audioBook, artwork: nil)
        let intent = makeIntent(mediaName: "Harry Potter", mediaItems: [item])

        let exp = expectation(description: "handle")
        let handler = try XCTUnwrap(self.handler)
        handler.handle(intent: intent) { response in
            XCTAssertEqual(response.code, .handleInApp)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func test_handle_audioUnavailable_returnsFailure() throws {
        launchState.markUnavailable()
        let item = INMediaItem(identifier: "file:///hp", title: "Harry Potter", type: .audioBook, artwork: nil)
        let intent = makeIntent(mediaName: "X", mediaItems: [item])

        let exp = expectation(description: "handle")
        let handler = try XCTUnwrap(self.handler)
        handler.handle(intent: intent) { response in
            XCTAssertEqual(response.code, .failureUnknownMediaType)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func test_handle_emptyMediaItems_returnsFailureUnknownMediaType() throws {
        let intent = makeIntent(mediaName: "X", mediaItems: nil)

        let exp = expectation(description: "handle")
        let handler = try XCTUnwrap(self.handler)
        handler.handle(intent: intent) { response in
            XCTAssertEqual(response.code, .failureUnknownMediaType)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)
    }
}
