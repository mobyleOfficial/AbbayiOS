//
//  SleepTimerTests+LastAwake.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Where the listener was last certainly awake when the timer stopped the book (#332 part 2):
/// their last deliberate action under the timer, never an automatic tick.
extension SleepTimerTests {
    // MARK: - Where the listener was last awake (#332 part 2)

    func test_stop_withoutMoves_isWhereItWasSet() {
        player.currentTime = 120
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.duration(60))
        player.currentTime = 180

        scheduler.advance(by: 60)

        XCTAssertEqual(stops.map(\.lastAwakeAt), [120])
        XCTAssertEqual(stops.map(\.stoppedAt), [180])
    }

    func test_stop_carriesTheLastDeliberateMove() {
        player.currentTime = 10
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.duration(600))
        scheduler.advance(by: 100)

        timer.listenerMoved(bookTime: 500)
        scheduler.advance(by: 500)

        XCTAssertEqual(stops.map(\.lastAwakeAt), [500])
    }

    func test_changingTheChoice_movesS() {
        player.currentTime = 10
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.duration(600))
        player.currentTime = 300
        timer.set(.duration(60))

        scheduler.advance(by: 60)

        XCTAssertEqual(stops.map(\.lastAwakeAt), [300])
    }

    func test_automaticTicks_dontMoveS() {
        player.currentTime = 10
        let timer = makeTimer()
        timer.playingChanged(true)
        timer.set(.duration(60))

        timer.timeChanged(bookTime: 40)
        scheduler.advance(by: 60)

        XCTAssertEqual(stops.map(\.lastAwakeAt), [10])
    }

    func test_movesWhileOff_areIgnored() {
        let timer = makeTimer()

        timer.listenerMoved(bookTime: 99)
        player.currentTime = 5
        timer.playingChanged(true)
        timer.set(.duration(60))
        scheduler.advance(by: 60)

        XCTAssertEqual(stops.map(\.lastAwakeAt), [5])
    }
}
