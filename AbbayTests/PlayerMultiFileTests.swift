//
//  PlayerMultiFileTests.swift
//  AbbayTests
//

@testable import Abbay
import AVFoundation
import XCTest

/// Multi-file (LibriVox) playback: book time maps to (chapter file, offset).
///
/// Like `PlayerChapterNavigationTests`, never waits for an item to become `readyToPlay`
/// (the remote URLs don't resolve). It asserts which file is queued and what gets saved.
final class PlayerMultiFileTests: XCTestCase {
    private final class MockChapterPrioritizer: ChapterPrioritizing {
        var calls: [(chapterIndex: Int, bookID: String)] = []

        func prioritize(chapterIndex: Int, ofBookID id: String) {
            calls.append((chapterIndex, id))
        }
    }

    private var flagSuite: UserDefaults?
    private var flagSuiteName: String?
    private var root: URL?
    private var saveUseCase: MockSaveAudioUseCase?
    private var bookmarkProvider: MockBookmarkProvider?
    private var prioritizer: MockChapterPrioritizer?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let name = "test.multifile.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        suite.removePersistentDomain(forName: name)
        flagSuiteName = name
        flagSuite = suite
        LaunchStateFlag.defaults = suite

        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayerMultiFileTests-\(UUID().uuidString)", isDirectory: true)
        saveUseCase = MockSaveAudioUseCase()
        bookmarkProvider = MockBookmarkProvider()
        prioritizer = MockChapterPrioritizer()
    }

    override func tearDownWithError() throws {
        NowPlayingManager.shared.clearNowPlaying()
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        if let name = flagSuiteName, let suite = flagSuite {
            suite.removePersistentDomain(forName: name)
        }
        LaunchStateFlag.defaults = AppGroup.defaults
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makePlayer() throws -> Player {
        Player(
            saveAudioUseCase: try XCTUnwrap(saveUseCase),
            intentDonor: MockIntentDonor(),
            librarySnapshotWriter: MockLibrarySnapshotWriter(),
            audioSessionActivator: MockAudioSessionActivator(),
            bookmarkProvider: try XCTUnwrap(bookmarkProvider),
            chapterPrioritizer: try XCTUnwrap(prioritizer),
            downloadsRoot: try XCTUnwrap(root)
        )
    }

    private func libriVoxBook(currentTime: Double = 0) -> AudioModel {
        AudioModel(
            title: "LibriVox",
            duration: 300,
            currentTime: currentTime,
            chapters: (0..<3).map { index in
                ChapterModel(
                    title: "c\(index)",
                    startTime: Double(index) * 100,
                    duration: 100,
                    remoteURL: URL(string: "https://example.org/c\(index).mp3")
                )
            },
            url: URL(string: "librivox://book/1"),
            librivoxID: "1"
        )
    }

    // MARK: - Tests

    func test_play_libriVoxBook_loadsChapterForSavedPosition() throws {
        let player = try makePlayer()
        var model = libriVoxBook(currentTime: 150)

        player.play(&model)

        XCTAssertEqual(player.currentItemURL, URL(string: "https://example.org/c1.mp3"))
    }

    func test_play_prefersDownloadedFile() throws {
        let root = try XCTUnwrap(root)
        var model = libriVoxBook()
        _ = try LibriVoxIdentity.directory(forBookID: "1", root: root)
        let local = try XCTUnwrap(LibriVoxIdentity.localFileURL(for: model.chapters[0], bookID: "1", root: root))
        try Data([0, 1, 2]).write(to: local)
        let player = try makePlayer()

        player.play(&model)

        XCTAssertEqual(player.currentItemURL, local)
    }

    func test_seek_acrossFileBoundary_loadsTargetChapterFile() throws {
        let player = try makePlayer()
        var model = libriVoxBook()
        player.play(&model)

        player.seek(250)

        XCTAssertEqual(player.currentItemURL?.lastPathComponent, "c2.mp3")
    }

    func test_playChapter_prioritizesThatChapter() throws {
        let player = try makePlayer()
        let prioritizer = try XCTUnwrap(prioritizer)
        var model = libriVoxBook()
        player.play(&model)

        XCTAssertTrue(player.playChapter(at: 2))

        let last = try XCTUnwrap(prioritizer.calls.last)
        XCTAssertEqual(last.chapterIndex, 2)
        XCTAssertEqual(last.bookID, "1")
    }

    func test_saveTime_persistsBookTime() throws {
        let player = try makePlayer()
        let saveUseCase = try XCTUnwrap(saveUseCase)
        var model = libriVoxBook()
        player.play(&model)

        player.seek(150)
        player.pause()

        let saved = try XCTUnwrap(saveUseCase.savedModels.last)
        XCTAssertTrue((100..<200).contains(saved.currentTime), "saved \(saved.currentTime), expected book time")
        XCTAssertEqual(player.currentTime, 150, accuracy: 1)
    }

    func test_play_libriVoxBook_doesNotCreateBookmark() throws {
        let player = try makePlayer()
        let bookmarkProvider = try XCTUnwrap(bookmarkProvider)
        var model = libriVoxBook()

        player.play(&model)

        XCTAssertEqual(bookmarkProvider.createCallCount, 0)
        XCTAssertNil(model.bookmarkData)
    }

    func test_play_importedBook_unchanged() throws {
        let player = try makePlayer()
        let url = try XCTUnwrap(URL(string: "file:///imported.m4b"))
        var model = AudioModel(title: "Imported", duration: 400, url: url)

        player.play(&model)

        XCTAssertEqual(player.currentItemURL, url)
        XCTAssertEqual(try XCTUnwrap(bookmarkProvider).createCallCount, 1)
        XCTAssertTrue(try XCTUnwrap(prioritizer).calls.isEmpty)
    }
}
