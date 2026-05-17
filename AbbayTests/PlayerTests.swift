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
}
