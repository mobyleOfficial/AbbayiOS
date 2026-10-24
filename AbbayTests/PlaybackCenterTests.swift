//
//  PlaybackCenterTests.swift
//  AbbayTests
//

@testable import Abbay
import Observation
import XCTest

/// The app-wide playback source. It subscribes to the player once and splits what it hears into
/// a slow `PlaybackState` (rows read it) and a ticking `PlaybackClock` (only the playing views read
/// it), so a clock tick never reaches a row that isn't playing.
@MainActor
final class PlaybackCenterTests: XCTestCase {
    private let otherURL = URL(string: "file:///vm/other.m4b")

    func test_subscribesToEachPlayerPublisherExactlyOnce() {
        let player = CountingMockPlayer()
        let center = PlaybackCenter(player: player)

        XCTAssertEqual(player.urlSubscriptionCount, 1)
        XCTAssertEqual(player.timeSubscriptionCount, 1)
        XCTAssertEqual(player.playingSubscriptionCount, 1)

        for tick in 0..<50 { player.emitTime(Double(tick)) }
        player.emitPlayUrl(ViewModelSupport.chaptered())
        player.emitPlayUrl(AudioModel(title: "Other", url: otherURL))
        player.emitPlayUrl(ViewModelSupport.chaptered())
        for index in 0..<10 { player.emitPlaying(index.isMultiple(of: 2)) }

        XCTAssertEqual(player.urlSubscriptionCount, 1)
        XCTAssertEqual(player.timeSubscriptionCount, 1)
        XCTAssertEqual(player.playingSubscriptionCount, 1)
        withExtendedLifetime(center) {}
    }

    /// The #116 lesson: a source created after the book was loaded never sees the play event.
    func test_alreadyLoadedBookAtInit_isSeeded() {
        let player = CountingMockPlayer()
        let model = ViewModelSupport.chaptered()
        player.url = model.url
        player.currentTime = 42
        let loadAudio = MockLoadAudioUseCase()
        loadAudio.stubs[ViewModelSupport.url?.absoluteString ?? ""] = model

        let center = PlaybackCenter(player: player, loadAudio: loadAudio)

        XCTAssertEqual(center.state.loadedBook?.url, model.url)
        XCTAssertEqual(center.clock.bookTime, 42)
    }

    func test_pauseOutsideTheApp_flipsIsPlayingWithoutATick() {
        let player = CountingMockPlayer()
        let center = PlaybackCenter(player: player)
        player.emitPlayUrl(ViewModelSupport.chaptered())

        player.emitPlaying(true)
        XCTAssertTrue(center.state.isPlaying)
        player.emitPlaying(false)

        XCTAssertFalse(center.state.isPlaying)
    }

    func test_tick_doesNotNotifyPlaybackStateObservers() {
        let player = CountingMockPlayer()
        let center = PlaybackCenter(player: player)
        player.emitPlayUrl(ViewModelSupport.chaptered())
        player.emitPlaying(true)
        var fired = false

        withObservationTracking({
            _ = center.state.loadedBook
            _ = center.state.isPlaying
        }, onChange: { fired = true })
        player.emitTime(1)
        player.emitTime(2)
        player.emitTime(3)

        XCTAssertFalse(fired, "a clock tick must not reach anything that only reads PlaybackState")
    }

    func test_tick_notifiesClockObservers() {
        let player = CountingMockPlayer()
        let center = PlaybackCenter(player: player)
        player.emitPlayUrl(ViewModelSupport.chaptered())
        var fired = false

        withObservationTracking({
            _ = center.clock.bookTime
        }, onChange: { fired = true })
        player.emitTime(1)
        player.emitTime(2)
        player.emitTime(3)

        XCTAssertTrue(fired)
    }

    func test_sameValue_doesNotRenotify() {
        let player = CountingMockPlayer()
        let center = PlaybackCenter(player: player)
        player.emitPlaying(true)
        var fired = false

        withObservationTracking({
            _ = center.state.isPlaying
        }, onChange: { fired = true })
        player.emitPlaying(true)

        XCTAssertFalse(fired, "Observation notifies on every set, so an equal value must not be assigned")
    }

    func test_chapterFollowsTime() {
        let player = CountingMockPlayer()
        let center = PlaybackCenter(player: player)
        player.emitPlayUrl(ViewModelSupport.chaptered())

        player.emitTime(150)

        XCTAssertEqual(center.clock.currentChapter, 1, "0/100/200: 150 s falls in the second chapter")
    }
}
