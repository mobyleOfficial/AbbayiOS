//
//  PlayerTests.swift
//  AbbayTests
//

@testable import Abbay
import AVFoundation
import XCTest

final class PlayerTests: XCTestCase {
    private var sessionActivator: MockAudioSessionActivator?
    private var donor: MockIntentDonor?
    private var snapshotWriter: MockLibrarySnapshotWriter?
    private var bookmarkProvider: MockBookmarkProvider?
    private var player: Player?
    /// The player's App Group store, and the launch flag over it.
    private let appGroup = InMemoryKeyValueStore()
    private var flag: LaunchStateFlag { .inMemory(appGroup) }

    override func setUpWithError() throws {
        try super.setUpWithError()
        let activator = MockAudioSessionActivator()
        let donorMock = MockIntentDonor()
        let writerMock = MockLibrarySnapshotWriter()
        let bookmarkMock = MockBookmarkProvider()

        sessionActivator = activator
        donor = donorMock
        snapshotWriter = writerMock
        bookmarkProvider = bookmarkMock

        player = Player(
            savePlaybackPositionUseCase: MockSavePlaybackPositionUseCase(),
            intentDonor: donorMock,
            librarySnapshotWriter: writerMock,
            audioSessionActivator: activator,
            bookmarkProvider: bookmarkMock,
            lastPlayed: .inMemory(appGroup),
            launchState: .inMemory(appGroup)
        )
    }

    override func tearDownWithError() throws {
        NowPlayingManager.shared.clearNowPlaying()
        try super.tearDownWithError()
    }

    func test_play_setActiveSucceedsWhenFlagWasFalse_keepsFlagFalse() throws {
        var model = AudioModel(url: URL(string: "file:///book.m4a"))
        XCTAssertFalse(flag.isUnavailable())

        let player = try XCTUnwrap(self.player)
        let activator = try XCTUnwrap(sessionActivator)
        let donorMock = try XCTUnwrap(donor)
        player.play(&model)

        XCTAssertEqual(activator.activateCallCount, 1)
        XCTAssertFalse(flag.isUnavailable())
        XCTAssertEqual(donorMock.donateCallCount, 1)
    }

    func test_play_setActiveSucceedsWhenFlagWasTrue_clearsFlag_playsAndDonates_recoveryHappyPath() throws {
        flag.markUnavailable()
        var model = AudioModel(url: URL(string: "file:///book.m4a"))

        let player = try XCTUnwrap(self.player)
        let activator = try XCTUnwrap(sessionActivator)
        let donorMock = try XCTUnwrap(donor)
        player.play(&model)

        XCTAssertEqual(activator.activateCallCount, 1)
        XCTAssertFalse(flag.isUnavailable())
        XCTAssertEqual(donorMock.donateCallCount, 1)
    }

    func test_play_sameURLReplay_savesLastPlayedEachTime() throws {
        var model = AudioModel(url: URL(string: "file:///book.m4a"))
        let player = try XCTUnwrap(self.player)
        player.play(&model)
        XCTAssertEqual(appGroup.object(forKey: LastPlayedStore.key) as? String, "file:///book.m4a")

        // Simulate the store being mutated elsewhere; same-URL play should re-save
        appGroup.set("file:///other.m4a", forKey: LastPlayedStore.key)
        player.play(&model)
        XCTAssertEqual(appGroup.object(forKey: LastPlayedStore.key) as? String, "file:///book.m4a")
    }

    func test_play_firstPlayOfBookWithoutBookmark_populatesBookmarkDataOnInoutModel_callsSnapshotRefresh() throws {
        var model = AudioModel(url: URL(string: "file:///book.m4a"))
        XCTAssertNil(model.bookmarkData)
        let bookmarkMock = try XCTUnwrap(bookmarkProvider)
        bookmarkMock.bookmarkToReturn = Data([7, 8, 9])

        let player = try XCTUnwrap(self.player)
        let writerMock = try XCTUnwrap(snapshotWriter)
        player.play(&model)

        XCTAssertEqual(model.bookmarkData, Data([7, 8, 9]))
        XCTAssertEqual(writerMock.refreshCallCount, 1)
        XCTAssertEqual(bookmarkMock.createCallCount, 1)
    }

    func test_play_firstPlayOfBookWithBookmark_doesNotRePopulate_doesNotCallSnapshotRefresh() throws {
        var model = AudioModel(url: URL(string: "file:///book.m4a"))
        model.bookmarkData = Data([1, 2, 3])

        let player = try XCTUnwrap(self.player)
        let writerMock = try XCTUnwrap(snapshotWriter)
        let bookmarkMock = try XCTUnwrap(bookmarkProvider)
        player.play(&model)

        XCTAssertEqual(writerMock.refreshCallCount, 0)
        XCTAssertEqual(bookmarkMock.createCallCount, 0)
        XCTAssertEqual(model.bookmarkData, Data([1, 2, 3]))
    }

    func test_play_setActiveThrows_setsFlag_doesNotDonate() throws {
        let activator = try XCTUnwrap(sessionActivator)
        activator.shouldThrow = true
        var model = AudioModel(url: URL(string: "file:///book.m4a"))

        let player = try XCTUnwrap(self.player)
        let donorMock = try XCTUnwrap(donor)
        player.play(&model)

        XCTAssertTrue(flag.isUnavailable())
        XCTAssertEqual(donorMock.donateCallCount, 0)
    }

    /// `cleanup()` clears the Now Playing info but `self.url` survives it, so a replay of the
    /// same book skips `updatePlayItem` -- the only writer of the gate before this fix.
    func test_play_afterCleanup_sameURL_restoresTheNowPlayingGate() throws {
        var model = AudioModel(title: "Book", url: URL(string: "file:///book.m4a"))
        let player = try XCTUnwrap(self.player)

        player.play(&model)
        XCTAssertNotNil(NowPlayingManager.shared.currentAudio)

        player.cleanup()
        XCTAssertNil(
            NowPlayingManager.shared.currentAudio,
            "cleanup() must drop the gate along with the system info"
        )

        player.play(&model)
        XCTAssertNotNil(
            NowPlayingManager.shared.currentAudio,
            "play() must refresh the gate even when the URL is unchanged"
        )
    }

    // MARK: - Stale models from the list (task 4 review I2)

    private func makePlayer(saving save: MockSavePlaybackPositionUseCase, bookmarks: MockBookmarkProvider) -> Player {
        Player(
            savePlaybackPositionUseCase: save,
            intentDonor: MockIntentDonor(),
            librarySnapshotWriter: MockLibrarySnapshotWriter(),
            audioSessionActivator: MockAudioSessionActivator(),
            bookmarkProvider: bookmarks,
            lastPlayed: .inMemory(appGroup),
            launchState: .inMemory(appGroup)
        )
    }

    /// A row passes the book as the list loaded it: no bookmark, an old position. Replaying the
    /// loaded book must reuse the bookmark the player already has, and must not write that old
    /// position over the one `pause` saved.
    func test_play_replayOfLoadedBookWithStaleModel_reusesBookmarkAndWritesNoPosition() {
        let save = MockSavePlaybackPositionUseCase()
        let bookmarks = MockBookmarkProvider()
        bookmarks.bookmarkToReturn = Data([7, 8, 9])
        let player = makePlayer(saving: save, bookmarks: bookmarks)
        let listCopy = AudioModel(title: "Book", currentTime: 0, url: URL(string: "file:///book.m4a"))
        var first = listCopy
        player.play(&first)
        XCTAssertEqual(bookmarks.createCallCount, 1)
        let writesAfterFirstPlay = save.calls.count

        var stale = listCopy
        player.play(&stale)

        XCTAssertEqual(bookmarks.createCallCount, 1, "the loaded book's bookmark must be reused")
        XCTAssertEqual(save.calls.count, writesAfterFirstPlay, "no position write on a replay")
        XCTAssertEqual(stale.bookmarkData, Data([7, 8, 9]), "the caller's model must carry the bookmark")
    }

    /// The list refreshes the outgoing book from storage on the play-URL event, so the player must
    /// have saved that book's position before announcing the new one.
    func test_bookSwitch_savesTheOutgoingPositionBeforeAnnouncingTheNewBook() throws {
        let save = MockSavePlaybackPositionUseCase()
        let player = makePlayer(saving: save, bookmarks: MockBookmarkProvider())
        let first = URL(string: "file:///a.m4a")
        var bookA = AudioModel(title: "A", url: first, bookmarkData: Data([1]))
        var bookB = AudioModel(title: "B", url: URL(string: "file:///b.m4a"), bookmarkData: Data([2]))
        player.play(&bookA)
        var savedBeforeAnnouncement: [URL?] = []
        let cancellable = player.playUrlSubjectPublisher.sink { _ in
            savedBeforeAnnouncement = save.calls.map(\.url)
        }

        player.play(&bookB)

        XCTAssertTrue(savedBeforeAnnouncement.contains(first), "A's position must be saved first")
        withExtendedLifetime(cancellable) {}
    }
}
