//
//  NowPlayingManagerTests.swift
//  AbbayTests
//

@testable import Abbay
import MediaPlayer
import XCTest

final class NowPlayingManagerTests: XCTestCase {
    private let model = AudioModel(title: "Book", url: URL(string: "file:///book.m4a"))

    override func tearDownWithError() throws {
        NowPlayingManager.shared.clearNowPlaying()
        try super.tearDownWithError()
    }

    func test_setPlayer_exposesCurrentAudioToTheIntentGate() {
        NowPlayingManager.shared.setPlayer(MockPlayer(), currentAudio: model)

        XCTAssertEqual(NowPlayingManager.shared.currentAudio?.title, "Book")
    }

    /// `currentAudio` gates PauseAbbayIntent, NextChapterIntent, PreviousChapterIntent and
    /// PlayChapterIntent. Leaving it set after the system info is cleared makes Siri answer
    /// "Paused." with nothing playing.
    func test_clearNowPlaying_resetsTheIntentGate() {
        NowPlayingManager.shared.setPlayer(MockPlayer(), currentAudio: model)
        XCTAssertNotNil(NowPlayingManager.shared.currentAudio)

        NowPlayingManager.shared.clearNowPlaying()

        XCTAssertNil(
            NowPlayingManager.shared.currentAudio,
            "clearNowPlaying must reset the playback gate, or Siri reports success with nothing playing"
        )
    }

    /// The lock screen's and CarPlay's toggle asks `Player.isPlaying(_:)`, which counts waiting to
    /// play while buffering as playing (the same mapping as the bar's play/pause). So a toggle
    /// pressed while the audio buffers pauses it, as the pause icon on screen promises.
    func test_togglePlayPause_whileBuffering_pauses() {
        let player = MockPlayer()
        player.isPlayingResult = Player.isPlaying(status: .waitingToPlayAtSpecifiedRate, reason: .toMinimizeStalls)
        NowPlayingManager.shared.setPlayer(player, currentAudio: model)

        let status = NowPlayingManager.shared.togglePlayPause()

        XCTAssertEqual(status, .success)
        XCTAssertEqual(player.pauseCallCount, 1)
        XCTAssertTrue(player.playCalls.isEmpty, "a buffering player is playing: the toggle must not play again")
    }

    // MARK: - Skip intervals (Settings)

    func test_setSkipIntervals_drivesTheRemoteCommandsAndTheirHandlers() {
        let player = MockPlayer()
        NowPlayingManager.shared.setPlayer(player, currentAudio: model)
        defer { NowPlayingManager.shared.setSkipIntervals(backward: 15, forward: 15) }

        NowPlayingManager.shared.setSkipIntervals(backward: 10, forward: 45)

        let commands = MPRemoteCommandCenter.shared()
        XCTAssertEqual(commands.skipBackwardCommand.preferredIntervals, [10])
        XCTAssertEqual(commands.skipForwardCommand.preferredIntervals, [45])
        XCTAssertEqual(NowPlayingManager.shared.skipBackward(), .success)
        XCTAssertEqual(NowPlayingManager.shared.skipForward(), .success)
        XCTAssertEqual(player.backwardSeconds, [10])
        XCTAssertEqual(player.forwardSeconds, [45])
    }

    /// Building the container applies the stored intervals, so the lock screen matches Settings from
    /// launch, not only after the first change.
    func test_appSettings_withLiveEffects_appliesTheStoredIntervals() {
        defer { NowPlayingManager.shared.setSkipIntervals(backward: 15, forward: 15) }
        let store = InMemoryKeyValueStore([AppSettings.Key.skipBackward: 30, AppSettings.Key.skipForward: 10])

        _ = AppSettings(store: store, effects: LiveSettingsEffects())

        XCTAssertEqual(MPRemoteCommandCenter.shared().skipBackwardCommand.preferredIntervals, [30])
        XCTAssertEqual(MPRemoteCommandCenter.shared().skipForwardCommand.preferredIntervals, [10])
    }

    // MARK: - Speed

    func test_changePlaybackRate_setsTheLoadedBooksSpeed() {
        let player = MockPlayer()
        NowPlayingManager.shared.setPlayer(player, currentAudio: model)

        XCTAssertEqual(NowPlayingManager.shared.changePlaybackRate(to: 1.5), .success)

        XCTAssertEqual(player.rateCalls, [1.5])
    }

    func test_changePlaybackRate_withNothingLoaded_fails() {
        let player = MockPlayer()
        NowPlayingManager.shared.setPlayer(player, currentAudio: nil)

        XCTAssertEqual(NowPlayingManager.shared.changePlaybackRate(to: 1.5), .commandFailed)
        XCTAssertTrue(player.rateCalls.isEmpty)
    }

    func test_changePlaybackRateCommand_offersThePresets() {
        let command = MPRemoteCommandCenter.shared().changePlaybackRateCommand
        _ = NowPlayingManager.shared

        XCTAssertTrue(command.isEnabled)
        XCTAssertEqual(command.supportedPlaybackRates.map(\.doubleValue), PlaybackSpeed.presets)
    }

    /// The lock screen extrapolates the clock by the published rate, so it must be the real speed.
    func test_updateNowPlaying_publishesTheRealRate() throws {
        NowPlayingManager.shared.updateNowPlaying(for: model, currentTime: 12, isPlaying: true, playbackRate: 1.75)

        let info = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1.75)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyDefaultPlaybackRate] as? Double, 1.75)

        NowPlayingManager.shared.updateNowPlaying(for: model, currentTime: 12, isPlaying: false, playbackRate: 1.75)

        let paused = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(paused[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
        XCTAssertEqual(paused[MPNowPlayingInfoPropertyDefaultPlaybackRate] as? Double, 1.75)
    }

    func test_clearNowPlaying_isIdempotent() {
        NowPlayingManager.shared.setPlayer(MockPlayer(), currentAudio: model)

        NowPlayingManager.shared.clearNowPlaying()
        NowPlayingManager.shared.clearNowPlaying()

        XCTAssertNil(NowPlayingManager.shared.currentAudio)
    }
}
