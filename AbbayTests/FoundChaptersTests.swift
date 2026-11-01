//
//  FoundChaptersTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Chapters found in a book's audio reach everything that holds the book: its Core Data row (and
/// Siri's snapshot), the player, the playback state, the presented player and the mark that offers
/// to remove them.
@MainActor
final class FoundChaptersTests: XCTestCase {
    private let bookURL = URL(fileURLWithPath: "/found-chapters-\(UUID().uuidString).mp3")
    private let anotherURL = URL(fileURLWithPath: "/another.mp3")
    private let found = [
        ChapterModel(title: "Chapter One", startTime: 0, duration: 70),
        ChapterModel(title: "Chapter Two", startTime: 70, duration: 130)
    ]

    override func tearDown() async throws {
        DeleteAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(AudioModel(url: bookURL))
        NowPlayingManager.shared.clearNowPlaying()
        try await super.tearDown()
    }

    // MARK: - Saving

    func test_saveChapters_replacesTheBooksChapters_andRefreshesTheSnapshot() throws {
        let url = bookURL
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter())
            .execute(AudioModel(title: "Plain", duration: 200, url: url))
        let snapshot = MockLibrarySnapshotWriter()
        let sut = SaveChaptersUseCase(snapshotWriter: snapshot)

        XCTAssertEqual(sut.execute(found, bookURL: url), found)
        XCTAssertEqual(LoadAudioUseCase().execute(url: url)?.chapters, found)
        XCTAssertEqual(snapshot.refreshCallCount, 1)

        XCTAssertEqual(sut.execute([], bookURL: url), [])
        XCTAssertEqual(LoadAudioUseCase().execute(url: url)?.chapters, [], "removed again")
        XCTAssertEqual(snapshot.refreshCallCount, 2)
    }

    func test_saveChapters_noSuchBook_writesNothing() {
        let snapshot = MockLibrarySnapshotWriter()
        let missing = URL(fileURLWithPath: "/never-saved-\(UUID().uuidString).mp3")

        XCTAssertNil(SaveChaptersUseCase(snapshotWriter: snapshot).execute(found, bookURL: missing))
        XCTAssertEqual(snapshot.refreshCallCount, 0)
    }

    /// Chapters found while the book is listened to: a chapter that is still there keeps where the
    /// listener left it (#299) when the list grows.
    func test_saveChapters_keepsTheResumeOffset_ofAChapterThatStartsWhereItDid() throws {
        let url = bookURL
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter())
            .execute(AudioModel(title: "Plain", duration: 200, url: url))
        let sut = SaveChaptersUseCase(snapshotWriter: MockLibrarySnapshotWriter())
        sut.execute(found, bookURL: url)
        SavePlaybackPositionUseCase().execute(
            url: url, currentTime: 40, bookmarkData: nil, chapter: ChapterPosition(index: 0, offset: 40)
        )

        let grown = [
            ChapterModel(title: "Chapter One", startTime: 0, duration: 70),
            ChapterModel(title: "Chapter Two", startTime: 70.2, duration: 60),
            ChapterModel(title: "Chapter Three", startTime: 130, duration: 70)
        ]
        let saved = sut.execute(grown, bookURL: url)

        XCTAssertEqual(saved?.map(\.resumeOffset), [40, nil, nil])
        XCTAssertEqual(LoadAudioUseCase().execute(url: url)?.chapters.map(\.resumeOffset), [40, nil, nil])
    }

    // MARK: - The mark

    func test_foundChapterMark_persists_andGoesWithTheBook() throws {
        let url = bookURL
        let store = InMemoryKeyValueStore()
        let settings = AppSettings(store: store)

        settings.setHasFoundChapters(true, for: url)
        XCTAssertTrue(AppSettings(store: store).hasFoundChapters(for: url), "kept across launches")

        settings.forgetReadAlong(for: url)
        XCTAssertFalse(settings.hasFoundChapters(for: url), "the book was deleted")
        XCTAssertFalse(AppSettings(store: store).hasFoundChapters(for: url))
    }

    // MARK: - The player and the screens

    func test_player_replaceChapters_theLoadedImportedBook_navigatesByThem() {
        let player = Player(
            savePlaybackPositionUseCase: MockSavePlaybackPositionUseCase(),
            intentDonor: MockIntentDonor(),
            librarySnapshotWriter: MockLibrarySnapshotWriter(),
            audioSessionActivator: MockAudioSessionActivator(),
            bookmarkProvider: MockBookmarkProvider(),
            lastPlayed: .inMemory(),
            launchState: .inMemory()
        )
        var book = AudioModel(title: "Plain", duration: 200, url: bookURL)
        player.play(&book)
        XCTAssertFalse(player.playChapter(at: 1), "no chapters yet")

        player.replaceChapters(found, ofBookAt: bookURL)

        XCTAssertTrue(player.playChapter(at: 1))
        XCTAssertEqual(NowPlayingManager.shared.currentAudio?.chapters, found, "Siri's and the lock screen's copy")

        player.replaceChapters([], ofBookAt: anotherURL)
        XCTAssertTrue(player.playChapter(at: 1), "another book's chapters change nothing here")
    }

    func test_playbackCenter_replaceChapters_updatesTheLoadedBook_andItsChapter() {
        let player = CountingMockPlayer()
        let center = PlaybackCenter(player: player)
        player.emitPlayUrl(AudioModel(title: "Plain", duration: 200, url: bookURL))
        player.emitTime(100)
        XCTAssertEqual(center.clock.currentChapter, 0)

        center.replaceChapters(found, ofBookAt: bookURL)

        XCTAssertEqual(center.state.loadedBook?.chapters, found)
        XCTAssertEqual(center.clock.currentChapter, 1, "100 s is in chapter two")
        XCTAssertEqual(player.replacedChapters.count, 1)
    }

    func test_presentation_chaptersChanged_updatesThePresentedBook_andClosesWhenNoneAreLeft() {
        let sut = PlayerPresentation()
        sut.open(AudioModel(title: "Plain", duration: 200, url: bookURL), animated: false)

        sut.chaptersChanged(found, ofBookAt: bookURL)
        XCTAssertEqual(sut.presentedBook?.chapters, found)
        sut.setChapters(open: true)
        XCTAssertTrue(sut.isShowingChapters)

        sut.chaptersChanged([], ofBookAt: bookURL)
        XCTAssertEqual(sut.presentedBook?.chapters, [])
        XCTAssertFalse(sut.isShowingChapters)
    }

    func test_presentation_chaptersChanged_anotherBook_isIgnored() {
        let sut = PlayerPresentation()
        sut.open(AudioModel(title: "Plain", duration: 200, url: bookURL), animated: false)

        sut.chaptersChanged(found, ofBookAt: anotherURL)

        XCTAssertEqual(sut.presentedBook?.chapters, [])
    }
}
