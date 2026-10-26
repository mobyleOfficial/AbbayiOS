//
//  PlayerPositionSaveTests.swift
//  AbbayTests
//

@testable import Abbay
import AVFoundation
import UIKit
import XCTest

/// The listening position is saved while playing, throttled, and when the app is interrupted or
/// sent to the background (#117), not only on pause.
///
/// Ticks are driven through `savePositionIfDue(isPlaying:)`, which the periodic time observer
/// calls, against an injected clock: the observer itself only fires while an item really plays.
final class PlayerPositionSaveTests: XCTestCase {
    private var save = MockSavePlaybackPositionUseCase()
    private var notificationCenter = NotificationCenter()
    private var now = Date(timeIntervalSinceReferenceDate: 0)
    /// Keeps every player alive to the end of the test: a released player saves from `deinit`,
    /// which would be counted as one of the saves under test.
    private var players: [Player] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        save = MockSavePlaybackPositionUseCase()
        notificationCenter = NotificationCenter()
        now = Date(timeIntervalSinceReferenceDate: 0)
    }

    override func tearDownWithError() throws {
        players.removeAll()
        NowPlayingManager.shared.clearNowPlaying()
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makePlayer(savePlaybackPositionUseCase: SavePlaybackPositionUseCaseProtocol? = nil) -> Player {
        let player = Player(
            savePlaybackPositionUseCase: savePlaybackPositionUseCase ?? save,
            intentDonor: MockIntentDonor(),
            librarySnapshotWriter: MockLibrarySnapshotWriter(),
            audioSessionActivator: MockAudioSessionActivator(),
            bookmarkProvider: MockBookmarkProvider(),
            notificationCenter: notificationCenter,
            now: { [unowned self] in self.now },
            lastPlayed: .inMemory(),
            launchState: .inMemory()
        )
        players.append(player)
        return player
    }

    /// A loaded book with a bookmark already, so `play` itself writes no position.
    private func loadedPlayer() -> Player {
        let player = makePlayer()
        var model = AudioModel(title: "Book", duration: 400, url: URL(string: "file:///book.m4b"), bookmarkData: Data([1]))
        player.play(&model)
        return player
    }

    /// One periodic-observer tick per second, `seconds` times.
    private func tick(_ player: Player, seconds: Int, isPlaying: Bool = true) {
        for _ in 0..<seconds {
            now = now.addingTimeInterval(1)
            player.savePositionIfDue(isPlaying: isPlaying)
        }
    }

    private func postInterruption(_ type: AVAudioSession.InterruptionType) {
        notificationCenter.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: type.rawValue]
        )
    }

    // MARK: - Throttled save while playing

    func test_playing_doesNotSaveOnEveryTick() {
        let player = loadedPlayer()
        let before = save.calls.count

        tick(player, seconds: Int(Player.positionSaveInterval) - 1)

        XCTAssertEqual(save.calls.count, before, "no save before the interval has passed")
    }

    func test_playing_savesOnceTheIntervalHasPassed() throws {
        let player = loadedPlayer()
        let before = save.calls.count

        tick(player, seconds: Int(Player.positionSaveInterval))

        XCTAssertEqual(save.calls.count, before + 1)
        let saved = try XCTUnwrap(save.calls.last)
        XCTAssertEqual(saved.url, URL(string: "file:///book.m4b"))
        XCTAssertNil(saved.bookmarkData, "a periodic save writes the position only")
    }

    func test_playing_savesAgainOnlyAfterAnotherInterval() {
        let player = loadedPlayer()
        let before = save.calls.count
        let interval = Int(Player.positionSaveInterval)

        tick(player, seconds: interval)
        tick(player, seconds: interval - 1)
        XCTAssertEqual(save.calls.count, before + 1)

        tick(player, seconds: 1)
        XCTAssertEqual(save.calls.count, before + 2)
    }

    func test_paused_ticksNeverSave() {
        let player = loadedPlayer()
        let before = save.calls.count

        tick(player, seconds: Int(Player.positionSaveInterval) * 3, isPlaying: false)

        XCTAssertEqual(save.calls.count, before, "a paused player already saved on pause; seeks tick too")
    }

    func test_aPauseRestartsTheInterval() {
        let player = loadedPlayer()
        let interval = Int(Player.positionSaveInterval)
        tick(player, seconds: interval - 2)

        player.pause()
        let afterPause = save.calls.count
        tick(player, seconds: interval - 1)

        XCTAssertEqual(save.calls.count, afterPause, "the pause just saved")
    }

    /// #176: a book whose file moved plays from the resolved URL, but its position goes to the row
    /// it was stored under, or it is never saved.
    func test_movedBook_savesUnderItsRowURL_notTheURLItPlaysFrom() throws {
        let player = makePlayer()
        let stored = URL(fileURLWithPath: "/position-save/book.m4b")
        let moved = URL(fileURLWithPath: "/position-save/moved/book.m4b")
        var model = AudioModel(title: "Book", duration: 400, url: stored, bookmarkData: Data([1]))
        model.resolvedURL = moved
        player.play(&model)

        player.pause()

        XCTAssertEqual(try XCTUnwrap(save.calls.last).url, stored)
    }

    func test_noBookLoaded_ticksSaveNothing() {
        let player = makePlayer()

        tick(player, seconds: Int(Player.positionSaveInterval) * 2)

        XCTAssertTrue(save.calls.isEmpty)
    }

    // MARK: - Interruption and background

    func test_interruptionBegan_saves() {
        _ = loadedPlayer()
        let before = save.calls.count

        postInterruption(.began)

        XCTAssertEqual(save.calls.count, before + 1)
    }

    func test_interruptionEnded_doesNotSave() {
        _ = loadedPlayer()
        let before = save.calls.count

        postInterruption(.ended)

        XCTAssertEqual(save.calls.count, before)
    }

    func test_didEnterBackground_saves() {
        _ = loadedPlayer()
        let before = save.calls.count

        notificationCenter.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(save.calls.count, before + 1)
    }

    // MARK: - Update-only

    /// The periodic save goes through the same update-only use case as `pause`, so a book deleted
    /// while it plays is not re-inserted by the next tick.
    func test_periodicSave_afterTheBookWasDeleted_insertsNoRow() {
        let model = AudioModel(title: "Deleted", duration: 400, url: URL(string: "file:///deleted-\(UUID().uuidString).m4b"), bookmarkData: Data([1]))
        let player = makePlayer(savePlaybackPositionUseCase: SavePlaybackPositionUseCase())
        var loaded = model
        player.play(&loaded)

        tick(player, seconds: Int(Player.positionSaveInterval) * 2)

        XCTAssertNil(LoadAudioUseCase().execute(url: model.url))
    }
}
