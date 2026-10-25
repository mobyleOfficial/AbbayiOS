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

    private func makeIntent(
        mediaName: String?,
        artistName: String? = nil,
        mediaItems: [INMediaItem]? = nil
    ) -> INPlayMediaIntent {
        INPlayMediaIntent(
            mediaItems: mediaItems, mediaContainer: nil, playShuffled: nil,
            playbackRepeatMode: .none, resumePlayback: nil,
            playbackQueueLocation: .now, playbackSpeed: nil,
            mediaSearch: INMediaSearch(
                mediaType: .audioBook, sortOrder: .unknown,
                mediaName: mediaName, artistName: artistName, albumName: nil,
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

    /// Siri passes the media name as spoken, extra words included (#201).
    func test_decide_queryWithExtraWords_andAuthor_returnsSingleMatch() throws {
        try writeSnapshot([
            LibrarySnapshotEntry(title: "Goblet of Fire", urlString: "file:///gof", bookmarkData: nil, artist: "J. K. Rowling"),
            LibrarySnapshotEntry(title: "Order of the Phoenix", urlString: "file:///ootp", bookmarkData: nil)
        ])
        let handler = try XCTUnwrap(self.handler)
        guard case .singleMatch(let item) = handler.decide(for: makeIntent(mediaName: "the goblet of fire by Rowling")) else {
            return XCTFail("expected singleMatch for a query with extra words")
        }
        XCTAssertEqual(item.identifier, "file:///gof")
    }

    /// "Play something by Jane Austen" (#207): the author's books, spoken in the media name or
    /// carried apart in `artistName`.
    func test_decide_authorOnly_disambiguatesAmongTheirBooks() throws {
        try writeSnapshot([
            LibrarySnapshotEntry(title: "Emma", urlString: "file:///emma", bookmarkData: nil, artist: "Jane Austen"),
            LibrarySnapshotEntry(title: "Dracula", urlString: "file:///dracula", bookmarkData: nil, artist: "Bram Stoker"),
            LibrarySnapshotEntry(title: "Persuasion", urlString: "file:///persuasion", bookmarkData: nil, artist: "Jane Austen")
        ])
        let handler = try XCTUnwrap(self.handler)
        for intent in [
            makeIntent(mediaName: "something by Jane Austen"),
            makeIntent(mediaName: "um livro da Jane Austen"),
            makeIntent(mediaName: nil, artistName: "Jane Austen")
        ] {
            guard case .disambiguation(let items) = handler.decide(for: intent) else {
                return XCTFail("expected disambiguation for \(String(describing: intent.mediaSearch))")
            }
            XCTAssertEqual(items.map(\.identifier), ["file:///emma", "file:///persuasion"])
        }
    }

    func test_decide_authorOnly_withTheirLastPlayed_playsIt() throws {
        try writeSnapshot([
            LibrarySnapshotEntry(title: "Emma", urlString: "file:///emma", bookmarkData: nil, artist: "Jane Austen"),
            LibrarySnapshotEntry(title: "Persuasion", urlString: "file:///persuasion", bookmarkData: nil, artist: "Jane Austen")
        ])
        lastPlayed.save(url: try XCTUnwrap(URL(string: "file:///persuasion")))
        let handler = try XCTUnwrap(self.handler)
        guard case .singleMatch(let item) = handler.decide(for: makeIntent(mediaName: nil, artistName: "Austen")) else {
            return XCTFail("expected the author's last-played book")
        }
        XCTAssertEqual(item.identifier, "file:///persuasion")
    }

    func test_decide_artistWithNoBook_isNoMatch_notResume() throws {
        try writeSnapshot([
            LibrarySnapshotEntry(title: "Emma", urlString: "file:///emma", bookmarkData: nil, artist: "Jane Austen")
        ])
        lastPlayed.save(url: try XCTUnwrap(URL(string: "file:///emma")))
        let handler = try XCTUnwrap(self.handler)
        XCTAssertEqual(handler.decide(for: makeIntent(mediaName: nil, artistName: "Agatha Christie")), .noMatch)
        XCTAssertEqual(handler.decide(for: makeIntent(mediaName: "something by Agatha Christie")), .noMatch)
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
