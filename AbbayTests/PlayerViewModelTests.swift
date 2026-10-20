//
//  PlayerViewModelTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// `PlayerViewModel` backs the full-screen player and had no tests.
final class PlayerViewModelTests: XCTestCase {
    private struct Harness {
        let viewModel: PlayerViewModel
        let observer: MockPlayerObserver
        let player: MockPlayer
    }

    private func makeHarness(currentTime: Double = 0, isPlaying: Bool = true) -> Harness {
        let model = ViewModelSupport.chaptered(currentTime: currentTime)
        let player = MockPlayer()
        player.url = model.url
        player.isPlayingResult = isPlaying
        let observer = MockPlayerObserver()
        observer.player = player
        return Harness(
            viewModel: PlayerViewModel(model, playerObserver: observer),
            observer: observer,
            player: player
        )
    }

    // MARK: - Chapter resolution

    func test_init_reportsChapterZeroIndexed() {
        let harness = makeHarness(currentTime: 250)
        let viewModel = harness.viewModel

        XCTAssertEqual(viewModel.currentChapter, 2, "250s falls in the third chapter, index 2")
    }

    /// The `time` parameter is never read -- the body resolves against `self.currentTime`. It
    /// happens to agree today because the only caller fires from an `onChange` on `currentTime`,
    /// but the signature is a lie and any other caller would be silently ignored.
    func test_setCurrentChapter_ignoresItsArgument() {
        let harness = makeHarness(currentTime: 10)
        let viewModel = harness.viewModel
        XCTAssertEqual(viewModel.currentChapter, 0)

        viewModel.setCurrentChapter(for: 350)

        XCTAssertEqual(
            viewModel.currentChapter,
            0,
            "350s is chapter 2, but the argument is discarded in favour of currentTime"
        )
    }

    // MARK: - Observation

    func test_init_doesNotTrackTimeWhenADifferentBookIsLoaded() {
        let model = ViewModelSupport.chaptered()
        let player = MockPlayer()
        player.url = URL(string: "file:///vm/other.m4b")
        let observer = MockPlayerObserver()
        observer.player = player

        _ = PlayerViewModel(model, playerObserver: observer)

        XCTAssertTrue(
            observer.timeSubscriptions.isEmpty,
            "the player screen must not track time for a book that is not loaded"
        )
    }

    func test_init_tracksTimeWhenItsOwnBookIsLoaded() {
        let harness = makeHarness()
        let observer = harness.observer

        XCTAssertFalse(observer.timeSubscriptions.isEmpty)
    }

    func test_willSeek_releasesTheTimeSubscription() {
        let harness = makeHarness()
        let viewModel = harness.viewModel
        let observer = harness.observer

        viewModel.willSeek()

        XCTAssertEqual(observer.cancelTimeCallCount, 1)
        XCTAssertTrue(observer.timeSubscriptions.isEmpty)
    }

    func test_seek_reinstatesTrackingAndDelegates() {
        let harness = makeHarness()
        let viewModel = harness.viewModel
        let observer = harness.observer
        let player = harness.player
        viewModel.willSeek()

        viewModel.seek(120)

        XCTAssertEqual(player.seekSeconds, [120])
        XCTAssertFalse(observer.timeSubscriptions.isEmpty, "tracking resumes after a seek")
    }

    func test_anotherBookStartsPlaying_clearsPlayingState() {
        let harness = makeHarness()
        let viewModel = harness.viewModel
        let observer = harness.observer
        observer.emitTime(10)
        XCTAssertTrue(viewModel.isPlaying)

        observer.emitPlayUrl(AudioModel(title: "Other", url: URL(string: "file:///vm/other.m4b")))

        XCTAssertFalse(viewModel.isPlaying)
    }

    // MARK: - Delegation

    func test_transportMethodsDelegateToThePlayer() {
        let harness = makeHarness()
        let viewModel = harness.viewModel
        let player = harness.player

        viewModel.play()
        viewModel.pause()
        viewModel.forward(withSeconds: 15)
        viewModel.backward(withSeconds: 30)
        viewModel.skipToNextChapter()
        viewModel.skipToPreviousChapter()

        XCTAssertEqual(player.playCalls.count, 1)
        XCTAssertEqual(player.pauseCallCount, 1)
        XCTAssertEqual(player.forwardSeconds, [15])
        XCTAssertEqual(player.backwardSeconds, [30])
        XCTAssertEqual(player.skipNextCallCount, 1)
        XCTAssertEqual(player.skipPreviousCallCount, 1)
    }
}
