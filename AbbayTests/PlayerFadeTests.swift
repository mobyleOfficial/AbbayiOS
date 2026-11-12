//
//  PlayerFadeTests.swift
//  AbbayTests
//

@testable import Abbay
import AVFoundation
import Combine
import XCTest

/// The sleep timer's fade (#332) on the real `Player`: a level under Abbay's own volume that
/// dims the queue player without ever being saved as the listener's volume, and the book-end
/// event the timer listens for. Asserts the queue player's gain; never waits for audio.
final class PlayerFadeTests: XCTestCase {
    private var root: URL?
    private var settings = AppSettings(store: InMemoryKeyValueStore())
    private var cancellables = Set<AnyCancellable>()

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayerFadeTests-\(UUID().uuidString)", isDirectory: true)
        settings = AppSettings(store: InMemoryKeyValueStore())
    }

    override func tearDownWithError() throws {
        cancellables.removeAll()
        NowPlayingManager.shared.clearNowPlaying()
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        try super.tearDownWithError()
    }

    private func makePlayer() throws -> Player {
        Player(
            savePlaybackPositionUseCase: MockSavePlaybackPositionUseCase(),
            intentDonor: MockIntentDonor(),
            librarySnapshotWriter: MockLibrarySnapshotWriter(),
            audioSessionActivator: MockAudioSessionActivator(),
            bookmarkProvider: MockBookmarkProvider(),
            downloadsRoot: try XCTUnwrap(root),
            speeds: settings,
            volumes: settings,
            lastPlayed: .inMemory(),
            launchState: .inMemory()
        )
    }

    func test_fadeLevel_scalesTheGain_withoutSavingTheVolume() throws {
        settings.volume = 0.6
        let player = try makePlayer()

        player.setFadeLevel(0.5)

        XCTAssertEqual(Double(player.requestedVolume), 0.3, accuracy: 0.001)
        XCTAssertEqual(settings.volume, 0.6, "the fade is never saved as the listener's volume")
        XCTAssertEqual(player.volume, 0.6)
        XCTAssertEqual(player.fadeLevel, 0.5)
    }

    func test_fadeLevel_scalesTheBoost() throws {
        settings.volume = 1.6
        let player = try makePlayer()
        let before = Double(player.requestedVolume) * player.boostGain

        player.setFadeLevel(0.5)

        XCTAssertEqual(Double(player.requestedVolume) * player.boostGain, before / 2, accuracy: 0.001)
        XCTAssertEqual(settings.volume, 1.6)
    }

    func test_setVolume_resetsTheFade() throws {
        let player = try makePlayer()
        player.setFadeLevel(0.2)

        player.setVolume(0.8)

        XCTAssertEqual(player.fadeLevel, 1, "the listener's change is heard at once")
        XCTAssertEqual(Double(player.requestedVolume), 0.8, accuracy: 0.001)
    }

    func test_fadeLevel_isClamped() throws {
        let player = try makePlayer()

        player.setFadeLevel(-1)
        XCTAssertEqual(player.fadeLevel, 0)
        XCTAssertEqual(player.requestedVolume, 0)

        player.setFadeLevel(2)
        XCTAssertEqual(player.fadeLevel, 1)
        XCTAssertEqual(player.requestedVolume, 1)
    }

    func test_bookDidEnd_publishes() throws {
        let player = try makePlayer()
        var ends = 0
        player.bookEndPublisher.sink { ends += 1 }.store(in: &cancellables)

        player.bookDidEnd()

        XCTAssertEqual(ends, 1)
    }
}
