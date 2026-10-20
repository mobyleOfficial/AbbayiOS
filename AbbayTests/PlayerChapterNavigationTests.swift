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
    private var flagSuite: UserDefaults?
    private var flagSuiteName: String?

    private func makePlayer() -> Player {
        Player(
            saveAudioUseCase: MockSaveAudioUseCase(),
            intentDonor: MockIntentDonor(),
            librarySnapshotWriter: MockLibrarySnapshotWriter(),
            audioSessionActivator: MockAudioSessionActivator(),
            bookmarkProvider: MockBookmarkProvider()
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

    override func setUpWithError() throws {
        try super.setUpWithError()
        let name = "test.chapternav.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        suite.removePersistentDomain(forName: name)
        flagSuiteName = name
        flagSuite = suite
        LaunchStateFlag.defaults = suite
    }

    override func tearDownWithError() throws {
        NowPlayingManager.shared.clearNowPlaying()
        if let name = flagSuiteName, let suite = flagSuite {
            suite.removePersistentDomain(forName: name)
        }
        LaunchStateFlag.defaults = AppGroup.defaults
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
    /// leaves `chapters` empty for such a file, and `currentChapter(for:)` still resolves to 0
    /// through its `?? 0` fallback -- so an unguarded subscript traps.
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
}
