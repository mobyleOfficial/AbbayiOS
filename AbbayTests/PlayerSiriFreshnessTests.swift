//
//  PlayerSiriFreshnessTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The player keeps Siri's signals fresh beyond play start (#127): a pause donates the book and
/// asks for a (throttled) context refresh, and crossing into another chapter while playing
/// donates again. Repeats inside a short window are `IntentDonor`'s to drop.
///
/// Chapter ticks are driven through `noteChapter(atBookTime:isPlaying:)`, which the periodic time
/// observer calls: the observer itself only fires while an item really plays.
final class PlayerSiriFreshnessTests: XCTestCase {
    private let donor = MockIntentDonor()
    private let siriContext = MockSiriContextRefresher()
    private var players: [Player] = []

    override func tearDownWithError() throws {
        players.removeAll()
        NowPlayingManager.shared.clearNowPlaying()
        try super.tearDownWithError()
    }

    private func makePlayer() -> Player {
        let player = Player(
            savePlaybackPositionUseCase: MockSavePlaybackPositionUseCase(),
            intentDonor: donor,
            librarySnapshotWriter: MockLibrarySnapshotWriter(),
            audioSessionActivator: MockAudioSessionActivator(),
            bookmarkProvider: MockBookmarkProvider(),
            lastPlayed: .inMemory(),
            launchState: .inMemory(),
            siriContext: siriContext
        )
        players.append(player)
        return player
    }

    private func chaptered() -> AudioModel {
        AudioModel(
            title: "Chaptered",
            duration: 300,
            chapters: [
                ChapterModel(title: "one", startTime: 0, duration: 100),
                ChapterModel(title: "two", startTime: 100, duration: 100),
                ChapterModel(title: "three", startTime: 200, duration: 100)
            ],
            url: URL(string: "file:///chaptered.m4b"),
            bookmarkData: Data([1])
        )
    }

    private func playing(_ model: AudioModel) -> Player {
        let player = makePlayer()
        var model = model
        player.play(&model)
        return player
    }

    // MARK: - Pause

    func test_pause_donatesTheLoadedBook() {
        let player = playing(chaptered())

        player.pause()

        XCTAssertEqual(donor.donateCallCount, 2, "play start, then the pause")
        XCTAssertEqual(donor.lastDonatedModel?.title, "Chaptered")
    }

    func test_pause_asksForAThrottledContextRefresh() {
        let player = playing(chaptered())

        player.pause()

        XCTAssertEqual(siriContext.dueReasons, [.pause])
        XCTAssertTrue(siriContext.nowReasons.isEmpty, "a pause never bypasses the throttle")
    }

    func test_pause_withNothingLoaded_donatesNothing() {
        let player = makePlayer()

        player.pause()

        XCTAssertEqual(donor.donateCallCount, 0)
    }

    // MARK: - Chapter boundaries

    func test_crossingIntoTheNextChapter_whilePlaying_donates() {
        let player = playing(chaptered())
        player.noteChapter(atBookTime: 50, isPlaying: true)
        player.noteChapter(atBookTime: 99, isPlaying: true)
        XCTAssertEqual(donor.donateCallCount, 1, "only the play start so far")

        player.noteChapter(atBookTime: 100, isPlaying: true)

        XCTAssertEqual(donor.donateCallCount, 2)
    }

    func test_theFirstTickAfterLoading_doesNotDonate() {
        let player = playing(chaptered())

        player.noteChapter(atBookTime: 150, isPlaying: true)

        XCTAssertEqual(donor.donateCallCount, 1, "play start already donated this chapter")
    }

    func test_pausedTicks_doNotDonate() {
        let player = playing(chaptered())
        player.noteChapter(atBookTime: 50, isPlaying: true)

        player.noteChapter(atBookTime: 150, isPlaying: false)

        XCTAssertEqual(donor.donateCallCount, 1)
    }

    func test_aBookWithoutChapters_neverDonatesOnTicks() {
        let player = playing(AudioModel(title: "Plain", duration: 300, url: URL(string: "file:///plain.mp3"), bookmarkData: Data([1])))

        player.noteChapter(atBookTime: 0, isPlaying: true)
        player.noteChapter(atBookTime: 250, isPlaying: true)

        XCTAssertEqual(donor.donateCallCount, 1)
    }

    func test_loadingAnotherBook_restartsChapterTracking() {
        let player = playing(chaptered())
        player.noteChapter(atBookTime: 150, isPlaying: true)

        var other = chaptered()
        other.url = URL(string: "file:///other.m4b")
        player.play(&other)
        player.noteChapter(atBookTime: 0, isPlaying: true)

        XCTAssertEqual(donor.donateCallCount, 2, "two play starts; the new book's first tick isn't a boundary")
    }
}
