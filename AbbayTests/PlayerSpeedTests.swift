//
//  PlayerSpeedTests.swift
//  AbbayTests
//

@testable import Abbay
import AVFoundation
import XCTest

/// Playback speed on the real `Player`: each book plays at its own speed (or the default for new
/// books), through the queue player's `defaultRate`, so it holds across pause and resume, seeks and
/// chapter files. Asserts the requested rates, never waits for audio (the URLs don't resolve).
final class PlayerSpeedTests: XCTestCase {
    private var root: URL?
    private var settings = AppSettings(store: InMemoryKeyValueStore())

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayerSpeedTests-\(UUID().uuidString)", isDirectory: true)
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
            lastPlayed: .inMemory(),
            launchState: .inMemory()
        )
    }

    private func importedBook(_ name: String = "speed") -> AudioModel {
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
            url: URL(string: "librivox://book/speed"),
            librivoxID: "speed"
        )
    }

    // MARK: - Loading a book

    func test_newBook_playsAtNormalSpeedByDefault() throws {
        let player = try makePlayer()
        var book = importedBook()

        player.play(&book)

        XCTAssertEqual(player.playbackRate, 1)
        XCTAssertEqual(player.requestedRates.defaultRate, 1)
        XCTAssertEqual(player.requestedRates.rate, 1)
    }

    func test_newBook_playsAtTheDefaultSpeedForNewBooks() throws {
        settings.defaultSpeed = 1.5
        let player = try makePlayer()
        var book = importedBook()

        player.play(&book)

        XCTAssertEqual(player.playbackRate, 1.5)
        XCTAssertEqual(player.requestedRates.rate, 1.5)
    }

    func test_bookWithItsOwnSpeed_playsAtIt() throws {
        settings.defaultSpeed = 1.5
        var book = importedBook()
        settings.setSpeed(2.25, for: book.url)
        let player = try makePlayer()

        player.play(&book)

        XCTAssertEqual(player.playbackRate, 2.25)
        XCTAssertEqual(player.requestedRates.rate, 2.25)
    }

    /// "Default for new books": a book takes the default the first time it plays and keeps it, so a
    /// later change of the default only reaches books not played yet.
    func test_firstPlay_pinsTheDefault_soALaterDefaultLeavesTheBookAlone() throws {
        settings.defaultSpeed = 1.5
        let player = try makePlayer()
        var played = importedBook("played")
        player.play(&played)

        settings.defaultSpeed = 2

        XCTAssertEqual(settings.speed(for: played.url), 1.5)
        XCTAssertEqual(settings.speed(for: importedBook("unplayed").url), 2)
        player.pause()
        player.play(&played)
        XCTAssertEqual(player.requestedRates.rate, 1.5)
    }

    /// Switching books switches speeds: each book keeps its own.
    func test_switchingBooks_appliesEachBooksSpeed() throws {
        var first = importedBook("first")
        var second = importedBook("second")
        settings.setSpeed(2, for: first.url)
        settings.setSpeed(0.8, for: second.url)
        let player = try makePlayer()

        player.play(&first)
        XCTAssertEqual(player.requestedRates.rate, 2)
        player.play(&second)

        XCTAssertEqual(player.playbackRate, 0.8)
        XCTAssertEqual(player.requestedRates.rate, 0.8, "the playing player takes the new book's speed at once")
    }

    // MARK: - Changing the speed

    func test_setPlaybackRate_whilePlaying_appliesAtOnce_andSavesItForTheBook() throws {
        let player = try makePlayer()
        var book = importedBook()
        player.play(&book)

        player.setPlaybackRate(1.75)

        XCTAssertEqual(player.requestedRates.rate, 1.75)
        XCTAssertEqual(player.requestedRates.defaultRate, 1.75)
        XCTAssertEqual(settings.speed(for: book.url), 1.75)
        XCTAssertEqual(settings.defaultSpeed, 1, "a book's speed is not the default for new books")
    }

    func test_setPlaybackRate_isSnapped() throws {
        let player = try makePlayer()
        var book = importedBook()
        player.play(&book)

        player.setPlaybackRate(9)

        XCTAssertEqual(player.playbackRate, PlaybackSpeed.maximum)
    }

    func test_setPlaybackRate_whilePaused_doesNotStartPlayback_andResumeUsesIt() throws {
        let player = try makePlayer()
        var book = importedBook()
        player.play(&book)
        player.pause()

        player.setPlaybackRate(1.25)

        XCTAssertEqual(player.requestedRates.rate, 0, "changing the speed must not resume")
        player.play(&book)
        XCTAssertEqual(player.requestedRates.rate, 1.25)
    }

    func test_speed_holdsAcrossPauseResumeAndSeek() throws {
        let player = try makePlayer()
        var book = importedBook()
        player.play(&book)
        player.setPlaybackRate(2)

        player.pause()
        player.play(&book)
        player.seek(120)
        player.forward(withSeconds: 30)

        XCTAssertEqual(player.requestedRates.rate, 2)
    }

    // MARK: - Multi-file books

    func test_multiFileBook_keepsItsSpeedAcrossChapterFiles() throws {
        var book = libriVoxBook()
        settings.setSpeed(1.5, for: book.url)
        let player = try makePlayer()

        player.play(&book)
        XCTAssertEqual(player.requestedRates.rate, 1.5)
        player.seek(250)

        XCTAssertEqual(player.currentItemURL?.lastPathComponent, "c2.mp3", "the seek loaded another file")
        XCTAssertEqual(player.requestedRates.rate, 1.5)
        XCTAssertTrue(player.playChapter(at: 0))
        XCTAssertEqual(player.requestedRates.rate, 1.5)
    }

    func test_multiFileBook_setPlaybackRate_savesUnderTheBooksIdentity() throws {
        let player = try makePlayer()
        var book = libriVoxBook()
        player.play(&book)

        player.setPlaybackRate(3)

        XCTAssertEqual(settings.speed(for: LibriVoxIdentity.bookURL(id: "speed")), 3)
    }
}
