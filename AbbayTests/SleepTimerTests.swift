//
//  SleepTimerTests.swift
//  AbbayTests
//

@testable import Abbay
import Combine
import XCTest

/// The sleep timer (#332): counts listening time only, fades Abbay's volume out, pauses, and
/// gives the volume back. Time is a hand-moved clock; the player is a mock.
@MainActor
final class SleepTimerTests: XCTestCase {
    private var player = MockPlayer()
    private var scheduler = ManualSleepTimerScheduler()
    private var book: AudioModel? = AudioModel(title: "Book", duration: 3600, url: URL(string: "file:///sleep.m4b"))
    private var events: [SleepTimerEvent] = []
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        player = MockPlayer()
        player.url = book?.url
        scheduler = ManualSleepTimerScheduler()
        events = []
        cancellables = []
    }

    private func makeTimer(firstDurationOverride: TimeInterval? = nil) -> SleepTimer {
        let timer = SleepTimer(
            player: player,
            loadedBook: { [unowned self] in self.book },
            scheduler: scheduler,
            fadeDuration: 5,
            firstDurationOverride: firstDurationOverride
        )
        timer.events.sink { [unowned self] in self.events.append($0) }.store(in: &cancellables)
        return timer
    }

    private var stops: [SleepTimerStop] {
        events.compactMap { if case let .stopped(stop) = $0 { return stop } else { return nil } }
    }

    // MARK: - Counting

    func test_duration_countsOnlyWhilePlaying() {
        let timer = makeTimer()
        timer.set(.duration(600))

        timer.playingChanged(true)
        scheduler.advance(by: 100)
        timer.playingChanged(false)
        scheduler.advance(by: 1000)
        timer.playingChanged(true)
        scheduler.advance(by: 100)

        XCTAssertEqual(timer.remaining() ?? -1, 400, accuracy: 0.001)
    }

    func test_pauseHolds_playResumes() {
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.duration(600))
        scheduler.advance(by: 100)
        timer.playingChanged(false)

        scheduler.advance(by: 3600)

        XCTAssertEqual(player.pauseCallCount, 0)
        XCTAssertEqual(timer.choice, .duration(600))
        XCTAssertEqual(timer.remaining() ?? -1, 500, accuracy: 0.001)

        timer.playingChanged(true)
        scheduler.advance(by: 500)
        XCTAssertEqual(player.pauseCallCount, 1, "play resumes the count")
    }

    // MARK: - The end

    func test_duration_fadesThenPauses() throws {
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.duration(60))

        scheduler.advance(by: 54)
        XCTAssertTrue(player.fadeLevels.isEmpty, "no fade before the last five seconds")

        scheduler.advance(by: 6)
        let ramp = player.fadeLevels.dropLast()
        XCTAssertGreaterThan(ramp.count, 2)
        XCTAssertEqual(ramp.last, 0, "silent before the pause")
        XCTAssertTrue(zip(ramp, ramp.dropFirst()).allSatisfy { $0 > $1 }, "\(ramp) only goes down")
        XCTAssertEqual(player.pauseCallCount, 1)
        XCTAssertEqual(player.fadeLevel, 1, "the listener's level is back for the next play")
        XCTAssertNil(timer.choice)
        let url = try XCTUnwrap(book?.url)
        XCTAssertEqual(stops, [SleepTimerStop(bookURL: url, stoppedAt: 0)])
    }

    func test_stop_carriesTheBookTime() {
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.duration(60))
        player.currentTime = 812

        scheduler.advance(by: 60)

        XCTAssertEqual(stops.map(\.stoppedAt), [812])
    }

    func test_volumeChangeDuringFade_stopsTheRamp_butStillPauses() {
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.duration(60))
        scheduler.advance(by: 57)
        XCTAssertFalse(player.fadeLevels.isEmpty)

        player.setVolume(0.7)
        let rampSoFar = player.fadeLevels.count
        scheduler.advance(by: 2.9)

        XCTAssertEqual(player.fadeLevels.count, rampSoFar, "the listener's level wins")
        XCTAssertEqual(player.pauseCallCount, 0)
        scheduler.advance(by: 0.1)
        XCTAssertEqual(player.pauseCallCount, 1, "the pause still lands")
        XCTAssertEqual(player.fadeLevel, 1)
    }

    func test_pauseDuringFade_finishesTheTimer_andRestoresTheLevel() {
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.duration(60))
        scheduler.advance(by: 57)

        timer.playingChanged(false)

        XCTAssertNil(timer.choice)
        XCTAssertEqual(player.fadeLevel, 1)
        XCTAssertEqual(stops.count, 1)
        scheduler.advance(by: 60)
        XCTAssertEqual(player.fadeLevels.last, 1, "nothing ramps after it finished")
    }

    // MARK: - Changing it

    func test_off_cancels() {
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.duration(60))
        scheduler.advance(by: 57)

        timer.set(nil)
        scheduler.advance(by: 600)

        XCTAssertNil(timer.choice)
        XCTAssertNil(timer.remaining())
        XCTAssertEqual(player.pauseCallCount, 0)
        XCTAssertEqual(player.fadeLevel, 1, "Off mid-fade gives the level back")
        XCTAssertTrue(stops.isEmpty)
    }

    func test_replacingTheChoice_restartsTheCount() {
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.duration(600))
        scheduler.advance(by: 100)

        timer.set(.duration(300))

        XCTAssertEqual(timer.remaining() ?? -1, 300, accuracy: 0.001)
    }

    func test_set_publishesSet() {
        let timer = makeTimer()

        timer.set(.duration(600))
        timer.set(nil)

        XCTAssertEqual(events, [.set(bookURL: book?.url), .set(bookURL: book?.url)])
    }

    func test_unload_cancels() {
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.duration(60))
        scheduler.advance(by: 57)

        timer.bookUnloaded()
        scheduler.advance(by: 60)

        XCTAssertNil(timer.choice)
        XCTAssertEqual(player.fadeLevel, 1)
        XCTAssertEqual(player.pauseCallCount, 0)
        XCTAssertTrue(stops.isEmpty, "a deleted book has nowhere to go back to")
    }

    func test_bookEnd_whileSet_stops() {
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.duration(3600))
        scheduler.advance(by: 100)

        timer.bookEnded()

        XCTAssertNil(timer.choice)
        XCTAssertEqual(stops.count, 1, "the listener likely slept through the end")
    }

    func test_bookEnd_whenOff_doesNothing() {
        let timer = makeTimer()

        timer.bookEnded()

        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Choices

    func test_choices_offerEndOfChapterOnlyWithChapters() {
        let timer = makeTimer()
        let durations = SleepTimerChoice.durations.map(SleepTimerChoice.duration)

        XCTAssertEqual(timer.choices(for: book), durations)
        var chaptered = book
        chaptered?.chapters = [ChapterModel(title: "One", startTime: 0, duration: 100)]
        XCTAssertEqual(timer.choices(for: chaptered), [.endOfChapter] + durations)
        XCTAssertEqual(SleepTimerChoice.durations, [300, 600, 900, 1800, 2700, 3600])
    }

    func test_firstDurationOverride_shortensFiveMinutes() {
        let timer = makeTimer(firstDurationOverride: 8)

        timer.set(.duration(300))
        XCTAssertEqual(timer.remaining() ?? -1, 8, accuracy: 0.001)
        timer.set(.duration(600))
        XCTAssertEqual(timer.remaining() ?? -1, 600, accuracy: 0.001)
    }
}
