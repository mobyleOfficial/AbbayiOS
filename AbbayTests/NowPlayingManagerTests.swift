//
//  NowPlayingManagerTests.swift
//  AbbayTests
//

@testable import Abbay
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

    func test_clearNowPlaying_isIdempotent() {
        NowPlayingManager.shared.setPlayer(MockPlayer(), currentAudio: model)

        NowPlayingManager.shared.clearNowPlaying()
        NowPlayingManager.shared.clearNowPlaying()

        XCTAssertNil(NowPlayingManager.shared.currentAudio)
    }
}
