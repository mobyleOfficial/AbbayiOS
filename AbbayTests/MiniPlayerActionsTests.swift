//
//  MiniPlayerActionsTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The bar's chapter swipes: left goes to the next chapter, right restarts the current one. A
/// `false` result means nothing happened, and the bar answers with a haptic.
final class MiniPlayerActionsTests: XCTestCase {
    /// Chapters at 0, 100 and 200.
    private let book = ViewModelSupport.chaptered()
    private let noChapters = AudioModel(title: "Plain", duration: 300, url: URL(string: "file:///vm/plain.mp3"))

    func test_nextChapter_onLastChapter_returnsFalseAndDoesNotCallPlayer() {
        let player = MockPlayer()

        let result = MiniPlayerActions.nextChapter(player: player, book: book, chapter: 2)

        XCTAssertFalse(result)
        XCTAssertEqual(player.skipNextCallCount, 0)
        XCTAssertTrue(player.seekSeconds.isEmpty)
    }

    func test_nextChapter_callsSkipToNextChapter() {
        let player = MockPlayer()

        let result = MiniPlayerActions.nextChapter(player: player, book: book, chapter: 0)

        XCTAssertTrue(result)
        XCTAssertEqual(player.skipNextCallCount, 1)
    }

    func test_restartChapter_seeksToChapterStart() {
        let player = MockPlayer()

        let result = MiniPlayerActions.restartChapter(player: player, book: book, chapter: 1)

        XCTAssertTrue(result)
        XCTAssertEqual(player.seekSeconds, [100])
        XCTAssertEqual(player.skipPreviousCallCount, 0, "restart is not 'previous chapter'")
    }

    func test_noChapters_bothReturnFalse() {
        let player = MockPlayer()

        XCTAssertFalse(MiniPlayerActions.nextChapter(player: player, book: noChapters, chapter: 0))
        XCTAssertFalse(MiniPlayerActions.restartChapter(player: player, book: noChapters, chapter: 0))
        XCTAssertEqual(player.skipNextCallCount, 0)
        XCTAssertTrue(player.seekSeconds.isEmpty)
    }

    func test_restartChapter_outOfRange_returnsFalse() {
        let player = MockPlayer()

        XCTAssertFalse(MiniPlayerActions.restartChapter(player: player, book: book, chapter: 7))
        XCTAssertTrue(player.seekSeconds.isEmpty)
    }

    // MARK: - Swipe recognition

    func test_swipe_pastThresholdHorizontal_isRecognized() {
        XCTAssertEqual(MiniPlayerActions.swipe(for: CGSize(width: -41, height: 10)), .next)
        XCTAssertEqual(MiniPlayerActions.swipe(for: CGSize(width: 41, height: -10)), .restart)
    }

    func test_swipe_shortOrMostlyVertical_isIgnored() {
        XCTAssertNil(MiniPlayerActions.swipe(for: CGSize(width: -39, height: 0)), "under 40 pt")
        XCTAssertNil(MiniPlayerActions.swipe(for: CGSize(width: 60, height: -80)), "vertical wins: Task 8's drag")
        XCTAssertNil(MiniPlayerActions.swipe(for: CGSize(width: 50, height: 50)), "a tie is not horizontal")
    }

    // MARK: - Subtitle

    func test_subtitle_showsOneBasedChapterAndTimeLeftInIt() {
        // Chapter two (index 1) spans 100–200: at 130 s there are 70 s left, shown as 2 min.
        let subtitle = MiniPlayerActions.subtitle(book: book, chapter: 1, bookTime: 130)

        XCTAssertTrue(subtitle.hasPrefix("Chapter 2 · "), subtitle)
        XCTAssertTrue(subtitle.hasSuffix(" left"), subtitle)
        XCTAssertTrue(subtitle.contains("2"), subtitle)
    }

    func test_subtitle_withoutChapters_showsTimeLeftInTheBook() {
        let subtitle = MiniPlayerActions.subtitle(book: noChapters, chapter: 0, bookTime: 0)

        XCTAssertFalse(subtitle.contains("Chapter"), subtitle)
        XCTAssertTrue(subtitle.contains("5"), "300 s left is 5 min: \(subtitle)")
    }

    func test_progress_isWithinTheCurrentChapter() {
        XCTAssertEqual(MiniPlayerActions.progress(book: book, chapter: 1, bookTime: 150), 0.5, accuracy: 0.0001)
        XCTAssertEqual(MiniPlayerActions.progress(book: noChapters, chapter: 0, bookTime: 75), 0.25, accuracy: 0.0001)
        XCTAssertEqual(MiniPlayerActions.progress(book: book, chapter: 0, bookTime: -5), 0)
        XCTAssertEqual(MiniPlayerActions.progress(book: AudioModel(), chapter: 0, bookTime: 5), 0)
    }
}
