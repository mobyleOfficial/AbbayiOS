//
//  FloatingPlayerViewModelTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// `FloatingPlayerViewModel` backs the mini player. It is a near-copy of `PlayerViewModel`;
/// the chapter-indexing divergence between them was #104 and is now resolved, leaving one
/// remaining difference pinned below.
final class FloatingPlayerViewModelTests: XCTestCase {
    private struct Harness {
        let viewModel: FloatingPlayerViewModel
        let observer: MockPlayerObserver
        let player: MockPlayer
    }

    private func makeHarness(currentTime: Double = 0) -> Harness {
        let model = ViewModelSupport.chaptered(currentTime: currentTime)
        let player = MockPlayer()
        player.url = model.url
        player.isPlayingResult = true
        let observer = MockPlayerObserver()
        observer.player = player
        return Harness(
            viewModel: FloatingPlayerViewModel(model, playerObserver: observer),
            observer: observer,
            player: player
        )
    }

    /// Now agrees with `PlayerViewModel` and `MediaViewModel`: every view model is 0-based, and
    /// `ChapterCountView` adds one where a counter is displayed (#104).
    func test_init_reportsChapterZeroIndexed() {
        let harness = makeHarness(currentTime: 250)
        let viewModel = harness.viewModel

        XCTAssertEqual(viewModel.currentChapter, 2, "250s falls in the third chapter, index 2")
    }

    /// The remaining divergence: it starts tracking unconditionally, where `PlayerViewModel`
    /// only tracks when its own book is the loaded one.
    func test_init_tracksTimeEvenWhenADifferentBookIsLoaded() {
        let model = ViewModelSupport.chaptered()
        let player = MockPlayer()
        player.url = URL(string: "file:///vm/other.m4b")
        let observer = MockPlayerObserver()
        observer.player = player

        _ = FloatingPlayerViewModel(model, playerObserver: observer)

        XCTAssertFalse(observer.timeSubscriptions.isEmpty)
    }

    func test_setCurrentChapter_ignoresItsArgument() {
        let harness = makeHarness(currentTime: 10)
        let viewModel = harness.viewModel
        let atInit = viewModel.currentChapter

        viewModel.setCurrentChapter(for: 350)

        XCTAssertEqual(viewModel.currentChapter, atInit, "the argument is discarded, as in PlayerViewModel")
    }

    func test_willSeek_releasesTheTimeSubscription() {
        let harness = makeHarness()
        let viewModel = harness.viewModel
        let observer = harness.observer

        viewModel.willSeek()

        XCTAssertEqual(observer.cancelTimeCallCount, 1)
    }

    func test_transportMethodsDelegateToThePlayer() {
        let harness = makeHarness()
        let viewModel = harness.viewModel
        let player = harness.player

        viewModel.play()
        viewModel.pause()
        viewModel.forward(withSeconds: 15)
        viewModel.backward(withSeconds: 30)
        viewModel.seek(99)
        viewModel.skipToNextChapter()
        viewModel.skipToPreviousChapter()

        XCTAssertEqual(player.playCalls.count, 1)
        XCTAssertEqual(player.pauseCallCount, 1)
        XCTAssertEqual(player.forwardSeconds, [15])
        XCTAssertEqual(player.backwardSeconds, [30])
        XCTAssertEqual(player.seekSeconds, [99])
        XCTAssertEqual(player.skipNextCallCount, 1)
        XCTAssertEqual(player.skipPreviousCallCount, 1)
    }
}
