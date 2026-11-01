//
//  ChapterResumeTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// #299: a chapter played again starts where it was left, unless it was never started or was
/// listened to the end. Covers the rule (`ChapterModel.resumeTime`), what the player saves, how it
/// tells a chapter played through from one jumped away from (`ChapterCompletion`), and where
/// `playChapter(at:)` lands.
///
/// Like `PlayerChapterNavigationTests`, never waits on `AVPlayer`: right after a seek,
/// `Player.currentTime` reads the seek's target.
final class ChapterResumeTests: XCTestCase {
    private let url = URL(string: "file:///resume.m4b")
    private var save = MockSavePlaybackPositionUseCase()
    private var resume = StubChapterResume()
    private var players: [Player] = []

    override func setUp() {
        super.setUp()
        save = MockSavePlaybackPositionUseCase()
        resume = StubChapterResume()
    }

    override func tearDown() {
        players.removeAll()
        NowPlayingManager.shared.clearNowPlaying()
        super.tearDown()
    }

    // MARK: - The rule

    func test_resumeTime_neverStarted_isTheChaptersStart() {
        XCTAssertEqual(chapter(offset: nil).resumeTime, 100)
        XCTAssertEqual(chapter(offset: 0).resumeTime, 100)
    }

    func test_resumeTime_partlyListened_isWhereItWasLeft() {
        XCTAssertEqual(chapter(offset: 42).resumeTime, 142)
    }

    func test_resumeTime_listenedToTheEnd_startsOver() {
        XCTAssertEqual(chapter(offset: 100).resumeTime, 100, "played through")
        let lastSeconds = chapter(offset: 100 - ChapterModel.finishedTolerance)
        XCTAssertEqual(lastSeconds.resumeTime, 100, "paused in its last seconds")
        XCTAssertEqual(chapter(offset: 94).resumeTime, 194)
    }

    func test_chapterPosition_isTheChapterAndTheOffsetIntoIt() {
        let book = chaptered()

        XCTAssertEqual(book.chapterPosition(at: 130), ChapterPosition(index: 1, offset: 30))
        XCTAssertEqual(book.chapterPosition(at: 0), ChapterPosition(index: 0, offset: 0))
        XCTAssertNil(AudioModel(duration: 400).chapterPosition(at: 30), "no chapters, nothing to save")
    }

    // MARK: - Played through or jumped away

    func test_completion_playingIntoTheNextChapter_finishesTheOneBefore() {
        let sut = ChapterCompletion()
        let book = chaptered()

        XCTAssertEqual(sut.tick(book, bookTime: 98.5, isPlaying: true), [], "first tick only records")
        XCTAssertEqual(sut.tick(book, bookTime: 99.5, isPlaying: true), [])
        XCTAssertEqual(sut.tick(book, bookTime: 100.5, isPlaying: true), [0])
        XCTAssertEqual(sut.tick(book, bookTime: 101.5, isPlaying: true), [], "once")
    }

    func test_completion_aSeekIntoTheNextChapter_finishesNothing() {
        let sut = ChapterCompletion()
        let book = chaptered()
        _ = sut.tick(book, bookTime: 99.5, isPlaying: true)

        sut.jumped()

        XCTAssertEqual(sut.tick(book, bookTime: 100.5, isPlaying: true), [])
    }

    /// The tick right after a seek can still report the old time; the next one is then a big step.
    func test_completion_aStaleTickAfterASeek_stillFinishesNothing() {
        let sut = ChapterCompletion()
        let book = chaptered()
        _ = sut.tick(book, bookTime: 40, isPlaying: true)

        sut.jumped()
        XCTAssertEqual(sut.tick(book, bookTime: 41, isPlaying: true), [], "stale: the seek hasn't landed")
        XCTAssertEqual(sut.tick(book, bookTime: 250, isPlaying: true), [], "a jump, not playback")
    }

    func test_completion_backwards_pausedOrAnotherBook_finishesNothing() {
        let sut = ChapterCompletion()
        let book = chaptered()
        var other = chaptered()
        other.url = URL(string: "file:///other.m4b")

        _ = sut.tick(book, bookTime: 100.5, isPlaying: true)
        XCTAssertEqual(sut.tick(book, bookTime: 99.5, isPlaying: true), [], "backwards")
        XCTAssertEqual(sut.tick(book, bookTime: 100.5, isPlaying: false), [], "paused")
        _ = sut.tick(book, bookTime: 99.5, isPlaying: true)
        XCTAssertEqual(sut.tick(other, bookTime: 100.5, isPlaying: true), [], "another book")
    }

    // MARK: - Player: saving

    func test_save_writesTheChapterThePlayheadIsIn() throws {
        let player = loaded(at: 130)

        player.pause()

        XCTAssertEqual(try XCTUnwrap(save.calls.last).chapter, ChapterPosition(index: 1, offset: 30))
    }

    func test_playingIntoTheNextChapter_savesTheOneBeforeAsFinished() throws {
        let player = loaded(at: 99)
        let before = save.calls.count

        player.noteChapter(atBookTime: 99.5, isPlaying: true)
        player.noteChapter(atBookTime: 100.5, isPlaying: true)

        XCTAssertEqual(save.calls.count, before + 1)
        let finished = try XCTUnwrap(save.calls.last).chapter
        XCTAssertEqual(finished, ChapterPosition(index: 0, offset: 100), "its full length")
    }

    /// Next and previous chapter save the chapter being left first, at the exact point left.
    func test_skips_saveTheChapterBeingLeft() throws {
        let player = loaded(at: 150)

        player.skipToNextChapter()
        XCTAssertEqual(try XCTUnwrap(save.calls.last).chapter, ChapterPosition(index: 1, offset: 50))
        XCTAssertEqual(player.currentTime, 200, "next still goes to the chapter's start")

        player.skipToPreviousChapter()
        XCTAssertEqual(try XCTUnwrap(save.calls.last).chapter, ChapterPosition(index: 2, offset: 0))
    }

    // MARK: - Player: playChapter

    func test_playChapter_resumesWhereTheChapterWasLeft() throws {
        let player = loaded(at: 130)
        resume.times[2] = 275

        XCTAssertTrue(player.playChapter(at: 2))

        XCTAssertEqual(player.currentTime, 275)
        let left = try XCTUnwrap(save.calls.last).chapter
        XCTAssertEqual(left, ChapterPosition(index: 1, offset: 30), "the chapter left")
        XCTAssertEqual(resume.asked, [2])
    }

    func test_playChapter_notSaved_fallsBackToTheLoadedCopy() {
        var book = chaptered()
        book.chapters[2].resumeOffset = 10
        let player = loaded(book, at: 130)
        resume.isSaved = false

        player.playChapter(at: 2)

        XCTAssertEqual(player.currentTime, 210)
    }

    /// The chapter already playing keeps playing: its saved offset trails the playhead.
    func test_playChapter_theCurrentChapter_doesNotMove() {
        let player = loaded(at: 130)
        resume.times[1] = 120

        XCTAssertTrue(player.playChapter(at: 1))

        XCTAssertEqual(player.currentTime, 130)
        XCTAssertEqual(resume.asked, [])
    }

    // MARK: - Helpers

    private func chapter(offset: Double?) -> ChapterModel {
        ChapterModel(title: "two", startTime: 100, duration: 100, resumeOffset: offset)
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
            url: url,
            bookmarkData: Data([1])
        )
    }

    private func loaded(_ book: AudioModel? = nil, at time: Double) -> Player {
        let player = Player(
            savePlaybackPositionUseCase: save,
            chapterResume: resume,
            intentDonor: MockIntentDonor(),
            librarySnapshotWriter: MockLibrarySnapshotWriter(),
            audioSessionActivator: MockAudioSessionActivator(),
            bookmarkProvider: MockBookmarkProvider(),
            lastPlayed: .inMemory(),
            launchState: .inMemory()
        )
        players.append(player)
        var model = book ?? chaptered()
        model.currentTime = time
        player.play(&model)
        return player
    }
}

/// Saved resume times by chapter; a chapter with none saved resumes at its start.
final class StubChapterResume: LoadChapterResumeUseCaseProtocol {
    var times: [Int: Double] = [:]
    /// `false` reads as a book not in the library.
    var isSaved = true
    private(set) var asked: [Int] = []

    func resumeTime(ofChapter index: Int, in book: AudioModel) -> Double? {
        asked.append(index)
        guard isSaved, book.chapters.indices.contains(index) else { return nil }
        return times[index] ?? book.chapters[index].startTime
    }
}
