//
//  NowPlayingManagerTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class NowPlayingManagerTests: XCTestCase {
    private let model = AudioModel(title: "Book", url: URL(string: "file:///book.m4a"))

    override func tearDownWithError() throws {
        NowPlayingManager.shared.clearNowPlaying()
        try super.tearDownWithError()
    }

    func test_setPlayer_exposesCurrentAudioToTheIntentGate() {
        NowPlayingManager.shared.setPlayer(MockPlayer(), currentAudio: model)

        XCTAssertEqual(NowPlayingManager.shared.currentAudio?.title, "Book")
    }

    /// `currentAudio` gates PauseAbbayIntent, NextChapterIntent, PreviousChapterIntent and
    /// PlayChapterIntent. Leaving it set after the system info is cleared makes Siri answer
    /// "Paused." with nothing playing.
    func test_clearNowPlaying_resetsTheIntentGate() {
        NowPlayingManager.shared.setPlayer(MockPlayer(), currentAudio: model)
        XCTAssertNotNil(NowPlayingManager.shared.currentAudio)

        NowPlayingManager.shared.clearNowPlaying()

        XCTAssertNil(
            NowPlayingManager.shared.currentAudio,
            "clearNowPlaying must reset the playback gate, or Siri reports success with nothing playing"
        )
    }

    func test_clearNowPlaying_isIdempotent() {
        NowPlayingManager.shared.setPlayer(MockPlayer(), currentAudio: model)

        NowPlayingManager.shared.clearNowPlaying()
        NowPlayingManager.shared.clearNowPlaying()

        XCTAssertNil(NowPlayingManager.shared.currentAudio)
    }
}
