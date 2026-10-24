//
//  PlayerPlayingStatusTests.swift
//  AbbayTests
//

@testable import Abbay
import AVFoundation
import XCTest

/// What the bar and the rows show as "playing". Waiting counts as playing only while the player
/// is buffering towards playback: a book whose audio can't load leaves the player waiting with
/// no item to play, and must not show "pause" forever.
final class PlayerPlayingStatusTests: XCTestCase {
    func test_playing_isPlaying() {
        XCTAssertTrue(Player.isPlaying(status: .playing, reason: nil))
    }

    func test_paused_isNotPlaying() {
        XCTAssertFalse(Player.isPlaying(status: .paused, reason: nil))
    }

    func test_waitingToMinimizeStalls_isPlaying() {
        XCTAssertTrue(Player.isPlaying(status: .waitingToPlayAtSpecifiedRate, reason: .toMinimizeStalls))
    }

    func test_waitingWhileEvaluatingBufferingRate_isPlaying() {
        XCTAssertTrue(Player.isPlaying(status: .waitingToPlayAtSpecifiedRate, reason: .evaluatingBufferingRate))
    }

    func test_waitingWithNoItemToPlay_isNotPlaying() {
        XCTAssertFalse(Player.isPlaying(status: .waitingToPlayAtSpecifiedRate, reason: .noItemToPlay))
    }

    func test_waitingForOtherReasons_isNotPlaying() {
        XCTAssertFalse(Player.isPlaying(status: .waitingToPlayAtSpecifiedRate, reason: nil))
        XCTAssertFalse(Player.isPlaying(status: .waitingToPlayAtSpecifiedRate, reason: .waitingForCoordinatedPlayback))
        XCTAssertFalse(Player.isPlaying(status: .waitingToPlayAtSpecifiedRate, reason: .interstitialEvent))
    }

    /// The seed `PlaybackCenter` reads at init goes through the same mapping: with nothing loaded,
    /// nothing is playing.
    func test_isPlayingURL_withNothingLoaded_isFalse() {
        let player = Player(
            savePlaybackPositionUseCase: MockSavePlaybackPositionUseCase(),
            intentDonor: MockIntentDonor(),
            librarySnapshotWriter: MockLibrarySnapshotWriter(),
            audioSessionActivator: MockAudioSessionActivator(),
            bookmarkProvider: MockBookmarkProvider()
        )

        XCTAssertFalse(player.isPlaying(URL(string: "file:///vm/none.m4b")))
        XCTAssertFalse(player.isPlaying(nil))
    }
}
