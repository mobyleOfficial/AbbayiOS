//
//  SleepTimerTests+EndOfChapter.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// *When current chapter ends* (#332): the chapter's listed end, re-aimed until the fade, and a
/// LibriVox file's own hand-off; and the book's end, which the player has already paused.
extension SleepTimerTests {
    // MARK: - End of chapter

    func useChapteredBook() {
        book?.chapters = [
            ChapterModel(title: "One", startTime: 0, duration: 100),
            ChapterModel(title: "Two", startTime: 100, duration: 150),
            ChapterModel(title: "Three", startTime: 250, duration: 150)
        ]
        book?.duration = 400
    }

    /// Pauses within `tolerance` of `seconds` from now, and not before.
    func assertPauses(
        after seconds: TimeInterval,
        tolerance: TimeInterval = 0.25,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let before = player.pauseCallCount
        scheduler.advance(by: seconds - tolerance)
        XCTAssertEqual(player.pauseCallCount, before, "paused early", file: file, line: line)
        scheduler.advance(by: tolerance * 2)
        XCTAssertEqual(player.pauseCallCount, before + 1, "didn't pause on time", file: file, line: line)
    }

    func test_endOfChapter_pausesAtTheChapterEnd() {
        useChapteredBook()
        player.currentTime = 30
        let timer = makeTimer()
        timer.playingChanged(true)

        timer.set(.endOfChapter)

        assertPauses(after: 70)
        XCTAssertNil(timer.choice)
    }

    func test_endOfChapter_followsASpeedChange() {
        useChapteredBook()
        player.currentTime = 30
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.endOfChapter)
        scheduler.advance(by: 20)

        player.playbackRate = 2
        timer.timeChanged(bookTime: 50)

        assertPauses(after: 25)
    }

    func test_endOfChapter_reaimsAfterAChapterJump() {
        useChapteredBook()
        player.currentTime = 30
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.endOfChapter)
        scheduler.advance(by: 10)

        timer.timeChanged(bookTime: 120)

        assertPauses(after: 130)
    }

    func test_endOfChapter_targetLocksOnceTheFadeBegins() {
        useChapteredBook()
        player.currentTime = 30
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.endOfChapter)
        scheduler.advance(by: 67)
        XCTAssertFalse(player.fadeLevels.isEmpty, "fading by now")

        // A LibriVox chapter file ends a moment early and the next one starts.
        timer.timeChanged(bookTime: 101)
        scheduler.advance(by: 3.1)

        XCTAssertEqual(player.pauseCallCount, 1, "the end didn't move to chapter two's")
        let ramp = player.fadeLevels.dropLast()
        XCTAssertTrue(zip(ramp, ramp.dropFirst()).allSatisfy { $0 > $1 }, "\(ramp) never rises")
    }

    func test_endOfChapter_withoutChapters_meansTheBookEnd() {
        player.currentTime = 3000
        let timer = makeTimer()
        timer.playingChanged(true)

        timer.set(.endOfChapter)

        assertPauses(after: 600)
    }

    func test_endOfChapter_reaimsWhenChaptersAreReplaced() {
        useChapteredBook()
        player.currentTime = 30
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.endOfChapter)

        book?.chapters = [
            ChapterModel(title: "Found one", startTime: 0, duration: 50),
            ChapterModel(title: "Found two", startTime: 50, duration: 350)
        ]
        player.currentTime = 40
        timer.chaptersChanged()

        assertPauses(after: 10)
    }

    func test_endOfChapter_pausedHolds() {
        useChapteredBook()
        player.currentTime = 30
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.endOfChapter)
        scheduler.advance(by: 10)
        timer.playingChanged(false)

        scheduler.advance(by: 600)

        XCTAssertEqual(player.pauseCallCount, 0)
        XCTAssertEqual(timer.choice, .endOfChapter)
    }

    func test_endOfChapter_inTheLastChapter_bookEndStops() {
        useChapteredBook()
        player.currentTime = 300
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.endOfChapter)

        timer.bookEnded()

        XCTAssertNil(timer.choice)
        XCTAssertEqual(stops.count, 1)
    }


    // MARK: - Review fixes: LibriVox hand-offs and the book's end

    /// A LibriVox file a few seconds shorter than its listed chapter: the queue moves on by itself
    /// before the listed end. The timer stops there, rather than playing into the next chapter.
    func test_endOfChapter_fileEndsBeforeTheFade_stopsAtTheHandOff() {
        useChapteredBook()
        player.currentTime = 30
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.endOfChapter)
        scheduler.advance(by: 55)
        XCTAssertTrue(player.fadeLevels.isEmpty, "8 s short: the fade hasn't begun")

        player.currentTime = 100
        timer.chapterEnded()

        XCTAssertEqual(player.pauseCallCount, 1)
        XCTAssertNil(timer.choice)
        XCTAssertEqual(stops.count, 1)
        scheduler.advance(by: 600)
        XCTAssertEqual(player.pauseCallCount, 1, "nothing re-aimed at chapter two's end")
    }

    func test_endOfChapter_fileEndsDuringTheFade_stopsAtTheHandOff() {
        useChapteredBook()
        player.currentTime = 30
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.endOfChapter)
        scheduler.advance(by: 67)
        XCTAssertFalse(player.fadeLevels.isEmpty, "2 s short: fading")

        timer.chapterEnded()

        XCTAssertEqual(player.pauseCallCount, 1, "paused at the hand-off, not 3 s into chapter two")
        XCTAssertEqual(player.fadeLevel, 1)
    }

    func test_chapterEnd_underADuration_doesNothing() {
        useChapteredBook()
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.duration(600))

        timer.chapterEnded()

        XCTAssertEqual(timer.choice, .duration(600))
        XCTAssertEqual(player.pauseCallCount, 0)
    }

    /// The player has already paused at the book's end and saved it as finished (#299): a second
    /// pause would save over that with a shorter position.
    func test_bookEnd_clearsWithoutPausingAgain() {
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.duration(3600))

        timer.bookEnded()

        XCTAssertEqual(player.pauseCallCount, 0)
        XCTAssertNil(timer.choice)
        XCTAssertEqual(stops.count, 1)
    }

    func test_bookEnd_duringTheFade_restoresTheLevel_withoutPausing() {
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.duration(60))
        scheduler.advance(by: 57)

        timer.bookEnded()

        XCTAssertEqual(player.pauseCallCount, 0)
        XCTAssertEqual(player.fadeLevel, 1)
    }
}
