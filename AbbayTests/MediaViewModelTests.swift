//
//  MediaViewModelTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// `MediaViewModel` drives every library row and had no tests.
final class MediaViewModelTests: XCTestCase {
    func test_init_seedsCurrentTimeFromTheModel() {
        let model = ViewModelSupport.chaptered(currentTime: 150)
        let observer = ViewModelSupport.observer(loaded: model)

        let viewModel = MediaViewModel(model, playerObserver: observer)

        XCTAssertEqual(viewModel.currentTime, 150)
    }

    func test_init_reportsChapterZeroIndexed() {
        let model = ViewModelSupport.chaptered(currentTime: 150)
        let observer = ViewModelSupport.observer(loaded: model)

        let viewModel = MediaViewModel(model, playerObserver: observer)

        XCTAssertEqual(viewModel.currentChapter, 1, "150s falls in the second chapter, index 1")
    }

    /// Regression guard for #104. `init` and the time subscription used to disagree -- 0-based
    /// in one, 1-based in the other -- so the row's counter jumped as soon as playback reported
    /// a time, and a three-chapter book read "0/3" at rest. Both are 0-based now; the 1-based
    /// display conversion lives in `ChapterCountView`.
    func test_initAndTimeUpdateAgreeOnTheChapterIndex() {
        let model = ViewModelSupport.chaptered(currentTime: 150)
        let observer = ViewModelSupport.observer(loaded: model)
        let viewModel = MediaViewModel(model, playerObserver: observer)
        let atInit = viewModel.currentChapter

        observer.emitPlayUrl(model)
        observer.emitTime(150)

        XCTAssertEqual(atInit, 1, "150s falls in the second chapter, index 1")
        XCTAssertEqual(
            viewModel.currentChapter,
            atInit,
            "the same position must resolve to the same chapter before and after a time update"
        )
    }

    func test_timeUpdate_tracksCurrentTimeAndPlayingState() {
        let model = ViewModelSupport.chaptered()
        let observer = ViewModelSupport.observer(loaded: model, isPlaying: true)
        let viewModel = MediaViewModel(model, playerObserver: observer)

        observer.emitPlayUrl(model)
        observer.emitTime(42)

        XCTAssertEqual(viewModel.currentTime, 42, accuracy: 0.01)
        XCTAssertTrue(viewModel.isPlaying)
    }

    func test_anotherBookStartsPlaying_stopsTrackingAndClearsPlayingState() throws {
        let model = ViewModelSupport.chaptered()
        let observer = ViewModelSupport.observer(loaded: model)
        let viewModel = MediaViewModel(model, playerObserver: observer)
        observer.emitPlayUrl(model)
        observer.emitTime(10)
        XCTAssertTrue(viewModel.isPlaying)

        let other = AudioModel(title: "Other", url: URL(string: "file:///vm/other.m4b"))
        observer.emitPlayUrl(other)

        XCTAssertFalse(viewModel.isPlaying, "a row must stop claiming to play when another book starts")
        XCTAssertEqual(observer.cancelTimeCallCount, 1, "its time subscription must be released")
    }

    func test_play_delegatesToThePlayer() throws {
        let model = ViewModelSupport.chaptered()
        let observer = ViewModelSupport.observer(loaded: model)
        let player = try XCTUnwrap(observer.player as? MockPlayer)
        let viewModel = MediaViewModel(model, playerObserver: observer)

        viewModel.play()

        XCTAssertEqual(player.playCalls.count, 1)
        XCTAssertEqual(player.playCalls.first?.url, model.url)
    }

    func test_pause_delegatesToThePlayer() throws {
        let model = ViewModelSupport.chaptered()
        let observer = ViewModelSupport.observer(loaded: model)
        let player = try XCTUnwrap(observer.player as? MockPlayer)
        let viewModel = MediaViewModel(model, playerObserver: observer)

        viewModel.pause()

        XCTAssertEqual(player.pauseCallCount, 1)
    }
}
