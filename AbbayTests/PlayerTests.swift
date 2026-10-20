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
    private var flagSuite: UserDefaults?
    private var flagSuiteName: String?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let name = "test.player.flag.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        suite.removePersistentDomain(forName: name)
        flagSuiteName = name
        flagSuite = suite
        LaunchStateFlag.defaults = suite

        let activator = MockAudioSessionActivator()
        let donorMock = MockIntentDonor()
        let writerMock = MockLibrarySnapshotWriter()
        let bookmarkMock = MockBookmarkProvider()

        sessionActivator = activator
        donor = donorMock
        snapshotWriter = writerMock
        bookmarkProvider = bookmarkMock

        player = Player(
            saveAudioUseCase: MockSaveAudioUseCase(),
            intentDonor: donorMock,
            librarySnapshotWriter: writerMock,
            audioSessionActivator: activator,
            bookmarkProvider: bookmarkMock
        )
    }

    override func tearDownWithError() throws {
        NowPlayingManager.shared.clearNowPlaying()
        if let name = flagSuiteName, let suite = flagSuite {
            suite.removePersistentDomain(forName: name)
        }
        LaunchStateFlag.defaults = AppGroup.defaults
        try super.tearDownWithError()
    }

    func test_play_setActiveSucceedsWhenFlagWasFalse_keepsFlagFalse() throws {
        var model = AudioModel(url: URL(string: "file:///book.m4a"))
        XCTAssertFalse(LaunchStateFlag.isUnavailable())

        let player = try XCTUnwrap(self.player)
        let activator = try XCTUnwrap(sessionActivator)
        let donorMock = try XCTUnwrap(donor)
        player.play(&model)

        XCTAssertEqual(activator.activateCallCount, 1)
        XCTAssertFalse(LaunchStateFlag.isUnavailable())
        XCTAssertEqual(donorMock.donateCallCount, 1)
    }

    func test_play_setActiveSucceedsWhenFlagWasTrue_clearsFlag_playsAndDonates_recoveryHappyPath() throws {
        LaunchStateFlag.markUnavailable()
        var model = AudioModel(url: URL(string: "file:///book.m4a"))

        let player = try XCTUnwrap(self.player)
        let activator = try XCTUnwrap(sessionActivator)
        let donorMock = try XCTUnwrap(donor)
        player.play(&model)

        XCTAssertEqual(activator.activateCallCount, 1)
        XCTAssertFalse(LaunchStateFlag.isUnavailable())
        XCTAssertEqual(donorMock.donateCallCount, 1)
    }

    func test_play_sameURLReplay_savesLastPlayedEachTime() throws {
        let storeSuiteName = "test.store.\(UUID().uuidString)"
        let storeSuite = try XCTUnwrap(UserDefaults(suiteName: storeSuiteName))
        let originalDefaults = LastPlayedStore.defaults
        LastPlayedStore.defaults = storeSuite
        defer {
            storeSuite.removePersistentDomain(forName: storeSuiteName)
            LastPlayedStore.defaults = originalDefaults
        }

        var model = AudioModel(url: URL(string: "file:///book.m4a"))
        let player = try XCTUnwrap(self.player)
        player.play(&model)
        XCTAssertEqual(storeSuite.string(forKey: LastPlayedStore.key), "file:///book.m4a")

        // Simulate the store being mutated elsewhere; same-URL play should re-save
        storeSuite.set("file:///other.m4a", forKey: LastPlayedStore.key)
        player.play(&model)
        XCTAssertEqual(storeSuite.string(forKey: LastPlayedStore.key), "file:///book.m4a")
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

        XCTAssertTrue(LaunchStateFlag.isUnavailable())
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
}
