//
//  PlayerChapterNavigationTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Chapter navigation: `skipToNextChapter`, `skipToPreviousChapter` and `playChapter(at:)`.
///
/// Deliberately avoids depending on `AVPlayer` reaching a ready state -- item loading is async
/// and would make these flaky. Everything here is the decision logic around `model.chapters`,
/// which is what the Siri intents and the remote-command handlers drive.
final class PlayerChapterNavigationTests: XCTestCase {
    private func makePlayer() -> Player {
        Player(
            savePlaybackPositionUseCase: MockSavePlaybackPositionUseCase(),
            intentDonor: MockIntentDonor(),
            librarySnapshotWriter: MockLibrarySnapshotWriter(),
            audioSessionActivator: MockAudioSessionActivator(),
            bookmarkProvider: MockBookmarkProvider(),
            lastPlayed: .inMemory(),
            launchState: .inMemory()
        )
    }

    private func chaptered() -> AudioModel {
        AudioModel(
            title: "Chaptered",
            duration: 400,
            chapters: [
                ChapterModel(title: "one", startTime: 0, duration: 100),
                ChapterModel(title: "two", startTime: 100, duration: 100),
                ChapterModel(title: "three", startTime: 200, duration: 200)
            ],
            url: URL(string: "file:///chaptered.m4b")
        )
    }

    private func chapterless() -> AudioModel {
        AudioModel(
            title: "Chapterless",
            duration: 400,
            chapters: [],
            url: URL(string: "file:///chapterless.mp3")
        )
    }

    override func tearDownWithError() throws {
        NowPlayingManager.shared.clearNowPlaying()
        try super.tearDownWithError()
    }

    // MARK: - No book loaded

    func test_skipToNextChapter_noBookLoaded_isANoOp() {
        makePlayer().skipToNextChapter()
    }

    func test_skipToPreviousChapter_noBookLoaded_isANoOp() {
        makePlayer().skipToPreviousChapter()
    }

    func test_playChapter_noBookLoaded_returnsFalse() {
        XCTAssertFalse(
            makePlayer().playChapter(at: 0),
            "Siri needs false here so it can speak a failure instead of silently doing nothing"
        )
    }

    // MARK: - Chapterless book (#102)

    /// A plain MP3 with no chapter metadata is the common case, not an edge case. `FileLoader`
    /// leaves `chapters` empty for such a file. `currentChapter(for:)` used to resolve that to 0
    /// through a `?? 0` fallback (it returns nil now, #101), and an unguarded subscript trapped.
    func test_skipToPreviousChapter_chapterlessBook_doesNotCrash() {
        let player = makePlayer()
        var model = chapterless()
        player.play(&model)

        player.skipToPreviousChapter()
    }

    func test_skipToNextChapter_chapterlessBook_doesNotCrash() {
        let player = makePlayer()
        var model = chapterless()
        player.play(&model)

        player.skipToNextChapter()
    }

    func test_playChapter_chapterlessBook_returnsFalse() {
        let player = makePlayer()
        var model = chapterless()
        player.play(&model)

        XCTAssertFalse(player.playChapter(at: 0))
    }

    // MARK: - playChapter bounds

    func test_playChapter_validIndex_returnsTrue() {
        let player = makePlayer()
        var model = chaptered()
        player.play(&model)

        XCTAssertTrue(player.playChapter(at: 0))
        XCTAssertTrue(player.playChapter(at: 2))
    }

    func test_playChapter_indexPastEnd_returnsFalse() {
        let player = makePlayer()
        var model = chaptered()
        player.play(&model)

        XCTAssertFalse(player.playChapter(at: 3), "the book has three chapters, 0...2")
        XCTAssertFalse(player.playChapter(at: 99))
    }

    func test_playChapter_negativeIndex_returnsFalse() {
        let player = makePlayer()
        var model = chaptered()
        player.play(&model)

        XCTAssertFalse(player.playChapter(at: -1))
    }

    // MARK: - Pressing twice before the first seek completes (#151)

    /// While a book plays, `AVPlayer` keeps reporting the old time until a seek lands (a paused
    /// one reports the target at once, which is why a paused test never caught this). The second
    /// press must aim from where the first one is going, or both target the same chapter.
    func test_skipToNextChapter_twiceQuicklyWhilePlaying_landsTwoChaptersAhead() async throws {
        var model = try await fixtureBook()
        let player = makePlayer()
        player.play(&model)
        try await waitUntil("playback starts") { player.currentTime > 0.1 }

        player.skipToNextChapter()
        player.skipToNextChapter()

        let start = model.chapters[2].startTime
        try await waitUntil("seek towards chapter 2") { player.currentTime >= start }
        XCTAssertEqual(model.currentChapter(for: player.currentTime), 2, "two presses, two chapters")
        player.pause()
    }

    /// The first press goes to the start of the chapter (more than 15 s in), the second from
    /// there to the previous chapter.
    func test_skipToPreviousChapter_twiceQuicklyWhilePlaying_goesBackAChapter() async throws {
        var model = try await fixtureBook()
        model.currentTime = model.chapters[2].startTime + 30
        let player = makePlayer()
        player.play(&model)
        try await waitUntil("playback starts") { player.currentTime > model.currentTime + 0.1 }

        player.skipToPreviousChapter()
        player.skipToPreviousChapter()

        let start = model.chapters[1].startTime
        try await waitUntil("seek towards chapter 1") { player.currentTime < model.chapters[2].startTime }
        XCTAssertEqual(model.currentChapter(for: player.currentTime), 1)
        XCTAssertGreaterThanOrEqual(player.currentTime, start)
        player.pause()
    }

    private func fixtureBook() async throws -> AudioModel {
        let url = try TestFixtures.christmastideURL()
        let loaded = await FileLoader(
            loadAudioUseCase: MockLoadAudioUseCase(),
            saveAudioUseCase: MockSaveAudioUseCase()
        ).load(url: url)
        return try XCTUnwrap(loaded)
    }

    // MARK: - Landing on the real fixture's chapter starts (#101)

    /// The one test here that waits for `AVPlayer`: chapter lookup is exact now (no `time + 1`), so a
    /// skip must land at or after the chapter's start, or the next skip computes the same target
    /// again. The fixture's starts (144.015, 288.012) are not whole seconds, which is the case
    /// that matters.
    func test_skipToNextChapter_realFixture_landsInsideEachChapter() async throws {
        let url = try TestFixtures.christmastideURL()
        let loaded = await FileLoader(
            loadAudioUseCase: MockLoadAudioUseCase(),
            saveAudioUseCase: MockSaveAudioUseCase()
        ).load(url: url)
        var model = try XCTUnwrap(loaded)
        let player = makePlayer()
        player.play(&model)
        player.pause()

        for expected in 1...2 {
            player.skipToNextChapter()
            let start = model.chapters[expected].startTime
            try await waitUntil("seek towards chapter \(expected)") { abs(player.currentTime - start) < 1 }
            XCTAssertGreaterThanOrEqual(player.currentTime, start, "landed before chapter \(expected)'s start")
            XCTAssertEqual(model.currentChapter(for: player.currentTime), expected)
        }
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 10,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("timed out waiting for \(description)")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
