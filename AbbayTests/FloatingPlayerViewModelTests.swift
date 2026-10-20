//
//  FloatingPlayerViewModelTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// `FloatingPlayerViewModel` backs the mini player and had no tests. It is a near-copy of
/// `PlayerViewModel` that diverges in two ways, both pinned here so a future refactor has to
/// decide deliberately rather than by accident.
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

    /// Divergence 1: this view model is 1-indexed where `PlayerViewModel` is 0-indexed. Correct
    /// for the "N/total" counter it renders, but the two must not be unified blindly -- the
    /// player's chapter list compares against a 0-based index.
    func test_init_reportsChapterOneIndexed() {
        let harness = makeHarness(currentTime: 250)
        let viewModel = harness.viewModel

        XCTAssertEqual(viewModel.currentChapter, 3, "250s is index 2, displayed as chapter 3 of 3")
    }

    /// Divergence 2: it starts tracking unconditionally, where `PlayerViewModel` only tracks
    /// when its own book is the loaded one.
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
