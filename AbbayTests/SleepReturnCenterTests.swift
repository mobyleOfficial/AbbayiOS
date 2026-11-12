//
//  SleepReturnCenterTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// *Back to where you fell asleep* (#332 part 2): a timer stop saves where the listener was last
/// awake, per book; the spot goes when it's used, dismissed, a new timer is set, playback starts far
/// from the stop, or half an hour of the book has played past it.
@MainActor
final class SleepReturnCenterTests: XCTestCase {
    private var player = MockPlayer()
    private var scheduler = ManualSleepTimerScheduler()
    private var settings = AppSettings(store: InMemoryKeyValueStore())
    private var savePosition = MockSavePlaybackPositionUseCase()
    private var loadedURL: URL?
    private let bookURL = URL(string: "file:///asleep.m4b")
    private var timer: SleepTimer?
    private var center: SleepReturnCenter?

    override func setUp() {
        super.setUp()
        player = MockPlayer()
        player.url = bookURL
        loadedURL = bookURL
        scheduler = ManualSleepTimerScheduler()
        settings = AppSettings(store: InMemoryKeyValueStore())
        savePosition = MockSavePlaybackPositionUseCase()
        let book = AudioModel(title: "Asleep", duration: 36_000, url: bookURL)
        let timer = SleepTimer(player: player, loadedBook: { book }, scheduler: scheduler)
        self.timer = timer
        center = SleepReturnCenter(
            settings: settings,
            timer: timer,
            player: player,
            savePosition: savePosition,
            loadedURL: { [unowned self] in loadedURL }
        )
    }

    /// Sets a timer at `awake`, and lets it stop the book at `stoppedAt`.
    private func fallAsleep(awake: Double = 600, stoppedAt: Double = 4200) throws {
        let timer = try XCTUnwrap(timer)
        player.currentTime = awake
        timer.playingChanged(true)
        timer.set(.duration(60))
        player.currentTime = stoppedAt
        scheduler.advance(by: 60)
        timer.playingChanged(false)
    }

    private var spot: SleepReturnSpot? { settings.sleepReturnSpot(for: bookURL) }

    func test_timerStop_savesTheSpot() throws {
        try fallAsleep()

        XCTAssertEqual(spot, SleepReturnSpot(returnTo: 600, stoppedAt: 4200))
    }

    func test_manualPause_savesNothing() throws {
        let timer = try XCTUnwrap(timer)
        timer.playingChanged(true)
        timer.set(.duration(600))

        timer.playingChanged(false)
        scheduler.advance(by: 600)

        XCTAssertNil(spot)
    }

    func test_newTimer_clears() throws {
        try fallAsleep()

        try XCTUnwrap(timer).set(.duration(900))

        XCTAssertNil(spot)
    }

    func test_turningTheTimerOff_keeps() throws {
        try fallAsleep()

        try XCTUnwrap(timer).set(nil)

        XCTAssertNotNil(spot, "Off isn't a new night")
    }

    /// Half asleep, the listener may press Play (or back 15 s) on the lock screen first.
    func test_playNearTheStop_keeps() throws {
        try fallAsleep()

        player.currentTime = 4200 - 120
        try XCTUnwrap(center).playingChanged(true)

        XCTAssertNotNil(spot)
    }

    func test_playFarFromTheStop_clears() throws {
        try fallAsleep()

        player.currentTime = 4200 + SleepReturnCenter.restartDistance + 1
        try XCTUnwrap(center).playingChanged(true)

        XCTAssertNil(spot)
    }

    func test_playingAnotherBook_keeps() throws {
        try fallAsleep()
        loadedURL = URL(string: "file:///other.m4b")

        player.currentTime = 0
        try XCTUnwrap(center).playingChanged(true)

        XCTAssertNotNil(spot, "the spot belongs to its book")
    }

    /// A scrub or skip while paused isn't listening: the spec keeps the spot until playback starts.
    func test_pausedJumpPastTheLimit_keeps() throws {
        try fallAsleep()
        let center = try XCTUnwrap(center)

        center.timeChanged(bookTime: 4200 + SleepReturnCenter.listeningLimit + 60)

        XCTAssertNotNil(spot)
    }

    func test_listeningLimit_clears() throws {
        try fallAsleep()
        let center = try XCTUnwrap(center)
        player.currentTime = 4200
        center.playingChanged(true)

        center.timeChanged(bookTime: 4200 + SleepReturnCenter.listeningLimit - 1)
        XCTAssertNotNil(spot)
        center.timeChanged(bookTime: 4200 + SleepReturnCenter.listeningLimit)

        XCTAssertNil(spot)
        XCTAssertEqual(SleepReturnCenter.restartDistance, 300)
        XCTAssertEqual(SleepReturnCenter.listeningLimit, 1800)
    }

    func test_goBack_seeksAndClears() throws {
        try fallAsleep()

        let target = try XCTUnwrap(center).goBack(for: bookURL)

        XCTAssertEqual(target, 600)
        XCTAssertEqual(player.seekSeconds, [600])
        XCTAssertNil(spot)
    }

    func test_goBack_doesNotPlay() throws {
        try fallAsleep()

        try XCTUnwrap(center).goBack(for: bookURL)

        XCTAssertTrue(player.playCalls.isEmpty)
    }

    /// After a relaunch the book isn't loaded: its saved position moves instead.
    func test_goBack_onAnUnloadedBook_savesThePosition() throws {
        try fallAsleep()
        loadedURL = nil

        try XCTUnwrap(center).goBack(for: bookURL)

        XCTAssertTrue(player.seekSeconds.isEmpty)
        XCTAssertEqual(savePosition.calls.map(\.currentTime), [600])
        XCTAssertEqual(savePosition.calls.map(\.url), [bookURL])
        XCTAssertNil(spot)
    }

    func test_goBack_withoutASpot_doesNothing() throws {
        XCTAssertNil(try XCTUnwrap(center).goBack(for: bookURL))
        XCTAssertTrue(player.seekSeconds.isEmpty)
    }

    func test_dismiss_clears() throws {
        try fallAsleep()

        try XCTUnwrap(center).dismiss(for: bookURL)

        XCTAssertNil(spot)
        XCTAssertTrue(player.seekSeconds.isEmpty)
    }
}
