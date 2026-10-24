//
//  PlayerNoticeTests.swift
//  AbbayTests
//

@testable import Abbay
import AVFoundation
import XCTest

/// #115 and #130: every way `Player.play` can fail tells the user, instead of a `print`.
///
/// The item failures are real: an `AVPlayerItem` for a file that isn't there fails on its own,
/// which is exactly what a moved file or an undownloaded chapter played offline looks like.
final class PlayerNoticeTests: XCTestCase {
    private var flagSuite: UserDefaults?
    private var flagSuiteName: String?
    private var root: URL?
    private var notices: MockNoticeReporter?
    private var activator: MockAudioSessionActivator?
    private var network: FakeNetworkPath?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let name = "test.player.notices.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        suite.removePersistentDomain(forName: name)
        flagSuiteName = name
        flagSuite = suite
        LaunchStateFlag.defaults = suite
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayerNoticeTests-\(UUID().uuidString)", isDirectory: true)
        notices = MockNoticeReporter()
        activator = MockAudioSessionActivator()
        network = FakeNetworkPath()
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
            savePlaybackPositionUseCase: MockSavePlaybackPositionUseCase(),
            intentDonor: MockIntentDonor(),
            librarySnapshotWriter: MockLibrarySnapshotWriter(),
            audioSessionActivator: try XCTUnwrap(activator),
            bookmarkProvider: MockBookmarkProvider(),
            downloadsRoot: try XCTUnwrap(root),
            noticeReporter: try XCTUnwrap(notices),
            networkPath: try XCTUnwrap(network)
        )
    }

    /// Waits for the first notice the player reports.
    private func waitForNotice(timeout: TimeInterval = 10) throws -> Notice? {
        let notices = try XCTUnwrap(notices)
        let reported = expectation(description: "a notice is reported")
        reported.assertForOverFulfill = false
        notices.onReport = { _ in reported.fulfill() }
        if !notices.notices.isEmpty { reported.fulfill() }
        wait(for: [reported], timeout: timeout)
        return notices.notices.first
    }

    /// Three chapters whose "remote" files don't exist, so streaming any of them fails.
    private func libriVoxBook() -> AudioModel {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-stream-\(UUID().uuidString)", isDirectory: true)
        return AudioModel(
            title: "LibriVox",
            duration: 300,
            chapters: (0..<3).map { index in
                ChapterModel(
                    title: "c\(index)",
                    startTime: Double(index) * 100,
                    duration: 100,
                    remoteURL: missing.appendingPathComponent("c\(index).mp3")
                )
            },
            url: URL(string: "librivox://book/1"),
            librivoxID: "1"
        )
    }

    // MARK: - Early returns

    func test_play_withNoURL_reportsThatTheBookCannotPlay() throws {
        let player = try makePlayer()
        var model = AudioModel(title: "Nowhere")

        player.play(&model)

        XCTAssertEqual(try XCTUnwrap(notices).notices, [.playbackFailed])
    }

    func test_play_whenTheAudioSessionWontActivate_reportsAudioUnavailable() throws {
        try XCTUnwrap(activator).shouldThrow = true
        let player = try makePlayer()
        var model = AudioModel(title: "Book", url: URL(string: "file:///book.m4a"))

        player.play(&model)

        XCTAssertEqual(try XCTUnwrap(notices).notices, [.audioUnavailable])
    }

    // MARK: - Imported files

    /// The bookmark no longer leads to a file (moved, renamed, deleted): say so, and how to fix it.
    func test_play_aFileThatIsNoLongerThere_reportsItMovedWithTheBooksTitle() throws {
        let player = try makePlayer()
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("gone-\(UUID().uuidString).m4b")
        var model = AudioModel(title: "Moved Book", url: missing)

        player.play(&model)

        XCTAssertEqual(try waitForNotice(), .fileMissing(title: "Moved Book"))
    }

    /// Pressing Play again after the banner has gone must say it again, not do nothing: the replay
    /// retries with a fresh item.
    func test_playAgain_afterAFailure_retriesAndReportsAgain() throws {
        let player = try makePlayer()
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("gone-\(UUID().uuidString).m4b")
        var model = AudioModel(title: "Moved Book", url: missing)
        player.play(&model)
        _ = try waitForNotice()
        let notices = try XCTUnwrap(notices)
        let firstCount = notices.notices.count
        let again = expectation(description: "reported again")
        again.assertForOverFulfill = false
        notices.onReport = { _ in again.fulfill() }

        player.play(&model)

        wait(for: [again], timeout: 10)
        XCTAssertGreaterThan(notices.notices.count, firstCount)
        XCTAssertEqual(notices.notices.last, .fileMissing(title: "Moved Book"))
    }

    /// The file is there but isn't playable audio: re-importing won't help, so don't suggest it.
    func test_play_aFileThatIsThereButUnreadable_reportsPlaybackFailed() throws {
        let player = try makePlayer()
        let root = try XCTUnwrap(root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let garbage = root.appendingPathComponent("garbage.m4b")
        try Data("not audio".utf8).write(to: garbage)
        var model = AudioModel(title: "Garbage", url: garbage)

        player.play(&model)

        XCTAssertEqual(try waitForNotice(), .playbackFailed)
    }

    func test_play_aRealFile_reportsNothing() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Christmastide", withExtension: "m4b"))
        let player = try makePlayer()
        var model = AudioModel(title: "Christmastide", url: fixture)
        let notices = try XCTUnwrap(notices)
        let reported = expectation(description: "no notice")
        reported.isInverted = true
        notices.onReport = { _ in reported.fulfill() }

        player.play(&model)

        wait(for: [reported], timeout: 2)
        player.pause()
    }

    // MARK: - LibriVox chapters (#130)

    /// Play offline on a chapter that isn't downloaded: the item fails, and the user hears why.
    func test_play_undownloadedChapterWhileOffline_reportsStreamingOffline() throws {
        try XCTUnwrap(network).isOnline = false
        let player = try makePlayer()
        var model = libriVoxBook()

        player.play(&model)

        XCTAssertEqual(try waitForNotice(), .streamingOffline)
    }

    func test_play_undownloadedChapterThatFailsOnline_reportsChapterFailed() throws {
        let player = try makePlayer()
        var model = libriVoxBook()

        player.play(&model)

        XCTAssertEqual(try waitForNotice(), .chapterFailed)
    }

    /// Only the chapter being played matters: the queued next chapter failing in the background
    /// must not produce a second, misleading notice.
    func test_play_failingChapter_reportsOnceForTheCurrentChapterOnly() throws {
        try XCTUnwrap(network).isOnline = false
        let player = try makePlayer()
        var model = libriVoxBook()

        player.play(&model)
        _ = try waitForNotice()
        RunLoop.main.run(until: Date().addingTimeInterval(1))

        XCTAssertEqual(try XCTUnwrap(notices).notices, [.streamingOffline])
    }
}
