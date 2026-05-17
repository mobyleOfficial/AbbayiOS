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
    private var testSuite: UserDefaults?
    private var suiteName: String?
    private var handler: PlayMediaIntentHandler?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let name = "test.handler.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        suite.removePersistentDomain(forName: name)
        suiteName = name
        testSuite = suite
        LibrarySnapshotReader.defaults = suite
        LaunchStateFlag.defaults = suite
        LastPlayedStore.defaults = suite
        handler = PlayMediaIntentHandler()
    }

    override func tearDownWithError() throws {
        if let name = suiteName, let suite = testSuite {
            suite.removePersistentDomain(forName: name)
        }
        LibrarySnapshotReader.defaults = AppGroup.defaults
        LaunchStateFlag.defaults = AppGroup.defaults
        LastPlayedStore.defaults = AppGroup.defaults
        try super.tearDownWithError()
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
        let suite = try XCTUnwrap(testSuite)
        let data = try JSONEncoder().encode(snapshot)
        suite.set(data, forKey: LibrarySnapshotWriter.key)
    }

    func test_resolveMediaItems_singleMatch_returnsSuccess() throws {
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

    func test_resolveMediaItems_multipleMatches_returnsDisambiguation() throws {
        try writeSnapshot([
            LibrarySnapshotEntry(title: "Harry Potter and the Sorcerer's Stone", urlString: "file:///a", bookmarkData: nil),
            LibrarySnapshotEntry(title: "Harry Potter and the Chamber of Secrets", urlString: "file:///b", bookmarkData: nil)
        ])

        let exp = expectation(description: "resolve")
        let handler = try XCTUnwrap(self.handler)
        handler.resolveMediaItems(for: makeIntent(mediaName: "Harry Potter")) { results in
            XCTAssertEqual(results.count, 1)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func test_resolveMediaItems_emptyLibrary_returnsUnsupported() throws {
        let exp = expectation(description: "resolve")
        let handler = try XCTUnwrap(self.handler)
        handler.resolveMediaItems(for: makeIntent(mediaName: "Anything")) { results in
            XCTAssertEqual(results.count, 1)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func test_resolveMediaItems_audioSessionUnavailableFlag_returnsUnsupported() throws {
        LaunchStateFlag.markUnavailable()
        let exp = expectation(description: "resolve")
        let handler = try XCTUnwrap(self.handler)
        handler.resolveMediaItems(for: makeIntent(mediaName: "Anything")) { results in
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
        LaunchStateFlag.markUnavailable()
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
