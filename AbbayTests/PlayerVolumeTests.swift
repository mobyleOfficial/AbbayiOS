//
//  PlayerVolumeTests.swift
//  AbbayTests
//

@testable import Abbay
import AVFoundation
import XCTest

/// Abbay's own volume on the real `Player`: one level for every book, applied to the queue player
/// (never the system volume), so a call on the Mac stays loud while the book is dimmed. Asserts the
/// queue player's `volume`, never waits for audio (the URLs don't resolve).
final class PlayerVolumeTests: XCTestCase {
    private var root: URL?
    private var settings = AppSettings(store: InMemoryKeyValueStore())

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayerVolumeTests-\(UUID().uuidString)", isDirectory: true)
        settings = AppSettings(store: InMemoryKeyValueStore())
    }

    override func tearDownWithError() throws {
        NowPlayingManager.shared.clearNowPlaying()
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

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

    private func importedBook(_ name: String = "volume") -> AudioModel {
        AudioModel(title: name, duration: 600, url: URL(string: "file:///\(name).m4b"))
    }

    private func libriVoxBook() -> AudioModel {
        AudioModel(
            title: "LibriVox",
            duration: 300,
            chapters: (0..<3).map { index in
                ChapterModel(
                    title: "c\(index)",
                    startTime: Double(index) * 100,
                    duration: 100,
                    remoteURL: URL(string: "https://example.org/c\(index).mp3")
                )
            },
            url: URL(string: "librivox://book/volume"),
            librivoxID: "volume"
        )
    }

    // MARK: - Tests

    func test_freshPlayer_playsAtFullVolume() throws {
        let player = try makePlayer()

        XCTAssertEqual(player.volume, 1)
        XCTAssertEqual(player.requestedVolume, 1)
    }

    /// The level saved last launch is there before any book loads.
    func test_savedVolume_isAppliedAtLaunch() throws {
        settings.volume = 0.3

        let player = try makePlayer()

        XCTAssertEqual(player.volume, 0.3)
        XCTAssertEqual(player.requestedVolume, 0.3, accuracy: 0.0001)
    }

    func test_setVolume_appliesAtOnce_andIsSaved() throws {
        let player = try makePlayer()
        var book = importedBook()
        player.play(&book)

        player.setVolume(0.45)

        XCTAssertEqual(player.requestedVolume, 0.45, accuracy: 0.0001)
        XCTAssertEqual(settings.volume, 0.45)
    }

    func test_setVolume_isSnapped() throws {
        let player = try makePlayer()

        player.setVolume(0.618)
        XCTAssertEqual(player.volume, 0.6)

        player.setVolume(4)
        XCTAssertEqual(player.volume, 1)
    }

    func test_setVolume_whilePaused_doesNotStartPlayback() throws {
        let player = try makePlayer()
        var book = importedBook()
        player.play(&book)
        player.pause()

        player.setVolume(0.2)

        XCTAssertEqual(player.requestedRates.rate, 0, "changing the volume must not resume")
        XCTAssertEqual(player.requestedVolume, 0.2, accuracy: 0.0001)
    }

    /// One level for the app, not per book: loading another book, or a book of chapter files,
    /// keeps it.
    func test_volume_holdsAcrossBooksAndChapterFiles() throws {
        let player = try makePlayer()
        var first = importedBook("first")
        player.play(&first)
        player.setVolume(0.25)

        var second = libriVoxBook()
        player.play(&second)
        player.playChapter(at: 2)

        XCTAssertEqual(player.volume, 0.25)
        XCTAssertEqual(player.requestedVolume, 0.25, accuracy: 0.0001)
    }

    /// Zero is a real choice (mute the book, keep the call), not "unset".
    func test_volumeZero_mutesTheBook() throws {
        let player = try makePlayer()

        player.setVolume(0)

        XCTAssertEqual(player.requestedVolume, 0)
        XCTAssertEqual(AppSettings(store: InMemoryKeyValueStore()).volume, 1)
        XCTAssertEqual(settings.volume, 0)
    }
}
