//
//  MultiFileQueueTests.swift
//  AbbayTests
//

@testable import Abbay
import AVFoundation
import XCTest

/// `MultiFileQueue.bookTime` while the queue player and the queue's bookkeeping disagree.
///
/// Like `PlayerMultiFileTests`, never waits for an item to become ready: the chapter URLs don't
/// resolve, so an item's own time reads zero and only the mapping to book time is under test.
final class MultiFileQueueTests: XCTestCase {
    private var player = AVQueuePlayer()
    private var root = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        try super.setUpWithError()
        player = AVQueuePlayer()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultiFileQueueTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        player.removeAllItems()
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func makeQueue() -> MultiFileQueue {
        MultiFileQueue(
            player: player,
            chapters: (0..<3).map { index in
                ChapterModel(
                    title: "c\(index)",
                    startTime: Double(index) * 100,
                    duration: 100,
                    remoteURL: URL(string: "https://example.org/c\(index).mp3")
                )
            },
            bookID: "1",
            downloadsRoot: root,
            prioritizer: NoopChapterPrioritizer(),
            onBookEnd: {}
        )
    }

    // MARK: - The queue advanced before the end-of-item notification (#118)

    /// `AVQueuePlayer` moves to the next file before the `.main`-queue end-of-item handler bumps
    /// `currentIndex`. In that window book time must not be the old chapter's start plus the new
    /// item's ~0, which would jump the bar back and let a save store a position a chapter early.
    func test_bookTime_afterTheQueueAdvancedAheadOfTheNotification_followsTheNewItem() {
        let queue = makeQueue()
        queue.seek(toBookTime: 150)
        queue.finishSeek(generation: queue.seekGeneration, finished: true)
        XCTAssertEqual(queue.currentIndex, 1)

        player.advanceToNextItem()

        XCTAssertEqual(queue.currentIndex, 1, "the handler hasn't run yet")
        XCTAssertGreaterThanOrEqual(queue.bookTime, 200, "book time was computed against the old chapter")
    }

    /// A seek's pending time belongs to the item it was made on: once the queue has moved past
    /// that item it is stale, even if the seek never completed.
    func test_bookTime_pendingSeekOnAnItemThatIsGone_isIgnored() {
        let queue = makeQueue()
        queue.seek(toBookTime: 150)

        player.advanceToNextItem()

        XCTAssertGreaterThanOrEqual(queue.bookTime, 200)
    }

    func test_bookTime_withNoCurrentItem_keepsTheLastKnownTime() {
        let queue = makeQueue()
        queue.seek(toBookTime: 150)
        XCTAssertEqual(queue.bookTime, 150)

        player.removeAllItems()

        XCTAssertEqual(queue.bookTime, 150, "must not fall back to the chapter's start or zero")
    }

    // MARK: - Seek completion (#130)

    func test_bookTime_duringASeek_isTheSeekTarget() {
        let queue = makeQueue()

        queue.seek(toBookTime: 150)

        XCTAssertEqual(queue.bookTime, 150)
    }

    /// An interrupted latest seek used to leave the pending time in place, freezing the displayed
    /// time until the next seek or chapter advance.
    func test_latestSeekInterrupted_releasesThePendingTime() {
        let queue = makeQueue()
        queue.seek(toBookTime: 150)

        queue.finishSeek(generation: queue.seekGeneration, finished: false)

        XCTAssertNil(queue.pendingBookTime, "book time must follow the item again")
    }

    func test_latestSeekFinished_releasesThePendingTime() {
        let queue = makeQueue()
        queue.seek(toBookTime: 150)

        queue.finishSeek(generation: queue.seekGeneration, finished: true)

        XCTAssertNil(queue.pendingBookTime)
    }

    func test_earlierSeekCompleting_keepsTheLatestTarget() {
        let queue = makeQueue()
        queue.seek(toBookTime: 150)
        let earlier = queue.seekGeneration
        queue.seek(toBookTime: 170)

        queue.finishSeek(generation: earlier, finished: true)
        queue.finishSeek(generation: earlier, finished: false)

        XCTAssertEqual(queue.pendingBookTime, 170)
        XCTAssertEqual(queue.bookTime, 170)
    }
}
