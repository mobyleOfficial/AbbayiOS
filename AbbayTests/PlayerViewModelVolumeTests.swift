//
//  PlayerViewModelVolumeTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The player screen's volume: the app's, not the shown book's, so it reaches the player whichever
/// book is shown, loaded or not.
@MainActor
final class PlayerViewModelVolumeTests: XCTestCase {
    func test_setVolume_goesToThePlayer_evenForABookThatIsNotLoaded() {
        let player = MockPlayer()
        let sut = PlayerViewModel(ViewModelSupport.chaptered(), state: PlaybackState(), player: player, downloads: nil)

        sut.setVolume(0.4, in: AppSettings(store: InMemoryKeyValueStore()))

        XCTAssertEqual(player.volumeCalls, [0.4])
    }

    func test_setVolume_withoutAPlayer_isSaved() {
        let settings = AppSettings(store: InMemoryKeyValueStore())
        let sut = PlayerViewModel(ViewModelSupport.chaptered(), state: PlaybackState(), player: nil, downloads: nil)

        sut.setVolume(0.7, in: settings)

        XCTAssertEqual(settings.volume, 0.7)
        XCTAssertEqual(sut.volume(in: settings), 0.7)
    }
}
