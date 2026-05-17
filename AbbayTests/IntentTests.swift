//
//  IntentTests.swift
//  AbbayTests
//

@testable import Abbay
import AppIntents
import XCTest

final class IntentTests: XCTestCase {
    private var player = MockPlayer()
    private var loader = MockLoadAudioUseCase()
    private var lister = MockLoadAllAudiosUseCase()
    private let suiteName = "abbay.tests.IntentTests"

    override func setUpWithError() throws {
        try super.setUpWithError()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        LastPlayedStore.defaults = defaults

        player = MockPlayer()
        loader = MockLoadAudioUseCase()
        lister = MockLoadAllAudiosUseCase()
        DependencyContainer.configure(
            with: MockDependencyContainer(player: player, loadAudio: loader, loadAllAudios: lister)
        )
    }

    override func tearDownWithError() throws {
        DependencyContainer.reset()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        LastPlayedStore.defaults = .standard
        // NowPlayingManager is a process singleton with stateful currentAudio;
        // reset between tests so case-order independence holds.
        NowPlayingManager.shared.setPlayer(player, currentAudio: nil)
        try super.tearDownWithError()
    }

    // NowPlayingManager API (verified against Abbay/Core/NowPlayingManager.swift on
    // current `feat/siri` baseline): `setPlayer(_ player: PlayerProtocol, currentAudio: AudioModel?)`.

    // Note: AppIntents' IntentDialog does not expose its text via public API,
    // so tests assert observable SIDE EFFECTS (player calls, store state,
    // loader.executeCalls) rather than the spoken string. Each scope-table
    // branch is uniquely identifiable via side effects alone — the dialog
    // text itself is verified by the manual checklist in Task 15.

    private func audio(title: String, url: String) -> AudioModel {
        var model = AudioModel()
        model.title = title
        model.url = URL(string: url)
        return model
    }

    // MARK: Resume

    func test_resume_dialogConstants_matchSpecVerbatim() {
        XCTAssertEqual(ResumeAbbayIntent.addBookDialog, "Add a book in Abbay first.")
        XCTAssertEqual(
            ResumeAbbayIntent.cannotFindDialog,
            "Cannot find that audiobook. It may have been removed or is not downloaded."
        )
        XCTAssertEqual(ResumeAbbayIntent.playingDialog(title: "Foo"), "Playing Foo.")
    }

    func test_resume_noLastPlayed_loaderNotCalledAndPlayerNotCalled() async throws {
        _ = try await ResumeAbbayIntent().perform()
        XCTAssertEqual(loader.executeCalls.count, 0)
        XCTAssertEqual(player.playCalls.count, 0)
    }

    func test_resume_lastPlayedSet_butLoaderReturnsNil_clearsStoreAndDoesNotPlay() async throws {
        let url = try XCTUnwrap(URL(string: "file:///gone.m4b"))
        LastPlayedStore.save(url: url)
        // loader has no stub for url → returns nil

        _ = try await ResumeAbbayIntent().perform()

        XCTAssertEqual(loader.executeCalls.compactMap { $0 }, [url])
        XCTAssertEqual(player.playCalls.count, 0)
        XCTAssertNil(LastPlayedStore.lastPlayedURL(), "store must be cleared to avoid stuck loop")
    }

    func test_resume_lastPlayedReachable_playsAndKeepsStore() async throws {
        let url = try XCTUnwrap(URL(string: "file:///book.m4b"))
        let book = audio(title: "My Book", url: url.absoluteString)
        LastPlayedStore.save(url: url)
        loader.stubs[url.absoluteString] = book

        _ = try await ResumeAbbayIntent().perform()

        XCTAssertEqual(player.playCalls.count, 1)
        XCTAssertEqual(player.playCalls.first?.url, url)
        XCTAssertEqual(LastPlayedStore.lastPlayedURL(), url)
    }

    // MARK: Pause

    func test_pause_dialogConstants_matchSpecVerbatim() {
        XCTAssertEqual(PauseAbbayIntent.nothingPlayingDialog, "Nothing is playing.")
        XCTAssertEqual(PauseAbbayIntent.pausedDialog, "Paused.")
    }

    func test_pause_noCurrentAudio_doesNotPause() async throws {
        NowPlayingManager.shared.setPlayer(player, currentAudio: nil)
        _ = try await PauseAbbayIntent().perform()
        XCTAssertEqual(player.pauseCallCount, 0)
    }

    func test_pause_currentAudioActive_pauses() async throws {
        let book = audio(title: "Book", url: "file:///b.m4b")
        NowPlayingManager.shared.setPlayer(player, currentAudio: book)
        _ = try await PauseAbbayIntent().perform()
        XCTAssertEqual(player.pauseCallCount, 1)
    }

    // MARK: Next chapter

    func test_nextChapter_dialogConstants_matchSpecVerbatim() {
        XCTAssertEqual(
            NextChapterIntent.nothingPlayingDialog,
            "Nothing is playing. Say 'Play in Abbay' to start."
        )
        XCTAssertEqual(NextChapterIntent.nextChapterDialog, "Next chapter.")
    }

    func test_nextChapter_noCurrentAudio_doesNotSkip() async throws {
        NowPlayingManager.shared.setPlayer(player, currentAudio: nil)
        _ = try await NextChapterIntent().perform()
        XCTAssertEqual(player.skipNextCallCount, 0)
    }

    func test_nextChapter_activeAudio_callsSkip() async throws {
        let book = audio(title: "Book", url: "file:///b.m4b")
        NowPlayingManager.shared.setPlayer(player, currentAudio: book)
        _ = try await NextChapterIntent().perform()
        XCTAssertEqual(player.skipNextCallCount, 1)
    }

    // MARK: Previous chapter

    func test_previousChapter_dialogConstants_matchSpecVerbatim() {
        XCTAssertEqual(
            PreviousChapterIntent.nothingPlayingDialog,
            "Nothing is playing. Say 'Play in Abbay' to start."
        )
        XCTAssertEqual(PreviousChapterIntent.previousChapterDialog, "Previous chapter.")
    }

    func test_previousChapter_noCurrentAudio_doesNotSkip() async throws {
        NowPlayingManager.shared.setPlayer(player, currentAudio: nil)
        _ = try await PreviousChapterIntent().perform()
        XCTAssertEqual(player.skipPreviousCallCount, 0)
    }

    func test_previousChapter_activeAudio_callsSkip() async throws {
        let book = audio(title: "Book", url: "file:///b.m4b")
        NowPlayingManager.shared.setPlayer(player, currentAudio: book)
        _ = try await PreviousChapterIntent().perform()
        XCTAssertEqual(player.skipPreviousCallCount, 1)
    }

    // MARK: Play by name

    func test_playByName_dialogConstants_matchSpecVerbatim() {
        XCTAssertEqual(
            PlayBookByNameIntent.noMatchDialog("Foo"),
            "No audiobook matches 'Foo'."
        )
        XCTAssertEqual(
            PlayBookByNameIntent.cannotFindDialog,
            "Cannot find that audiobook. It may have been removed or is not downloaded."
        )
        XCTAssertEqual(
            PlayBookByNameIntent.playingDialog(title: "Foo"),
            "Playing Foo."
        )
    }

    func test_playByName_noMatch_doesNotPlay_doesNotClearStore() async throws {
        let saved = try XCTUnwrap(URL(string: "file:///saved.m4b"))
        LastPlayedStore.save(url: saved)
        lister.stub = []  // empty library → fuzzyMatch returns nil

        var intent = PlayBookByNameIntent()
        intent.bookName = "anything"
        _ = try await intent.perform()

        XCTAssertEqual(player.playCalls.count, 0)
        XCTAssertEqual(LastPlayedStore.lastPlayedURL(), saved, "no-match must not touch the store")
    }

    func test_playByName_unreachable_andIsLastPlayed_clearsStore() async throws {
        let url = try XCTUnwrap(URL(string: "file:///gone.m4b"))
        let book = audio(title: "Gone Book", url: url.absoluteString)
        lister.stub = [book]
        LastPlayedStore.save(url: url)
        // loader has no stub for url → returns nil (file unreachable)

        var intent = PlayBookByNameIntent()
        intent.bookName = "Gone Book"
        _ = try await intent.perform()

        XCTAssertNil(LastPlayedStore.lastPlayedURL(), "store must be cleared when the dead match was the saved pointer")
        XCTAssertEqual(player.playCalls.count, 0)
    }

    func test_playByName_unreachable_andNotLastPlayed_doesNotClearStore() async throws {
        let saved = try XCTUnwrap(URL(string: "file:///saved.m4b"))
        let dead = try XCTUnwrap(URL(string: "file:///dead.m4b"))
        let book = audio(title: "Dead Book", url: dead.absoluteString)
        lister.stub = [book]
        LastPlayedStore.save(url: saved)
        // loader has no stub for dead.absoluteString → returns nil

        var intent = PlayBookByNameIntent()
        intent.bookName = "Dead Book"
        _ = try await intent.perform()

        XCTAssertEqual(
            LastPlayedStore.lastPlayedURL(),
            saved,
            "store must NOT be cleared when the dead match was a different book"
        )
        XCTAssertEqual(player.playCalls.count, 0)
    }

    func test_playByName_reachable_plays() async throws {
        let url = try XCTUnwrap(URL(string: "file:///hp.m4b"))
        let book = audio(title: "Harry Potter", url: url.absoluteString)
        lister.stub = [book]
        loader.stubs[url.absoluteString] = book

        var intent = PlayBookByNameIntent()
        intent.bookName = "Harry Potter"
        _ = try await intent.perform()

        XCTAssertEqual(player.playCalls.count, 1)
        XCTAssertEqual(player.playCalls.first?.url, url)
    }

    // MARK: - LaunchStateFlag gate

    private func withUnavailableFlag(_ body: () async throws -> Void) async throws {
        let flagSuiteName = "test.flag.\(UUID().uuidString)"
        let flagSuite = try XCTUnwrap(UserDefaults(suiteName: flagSuiteName))
        let originalFlagDefaults = LaunchStateFlag.defaults
        LaunchStateFlag.defaults = flagSuite
        LaunchStateFlag.markUnavailable()
        defer {
            flagSuite.removePersistentDomain(forName: flagSuiteName)
            LaunchStateFlag.defaults = originalFlagDefaults
        }
        try await body()
    }

    func test_resumeAbbayIntent_audioUnavailable_doesNotCallPlayer() async throws {
        try await withUnavailableFlag {
            _ = try await ResumeAbbayIntent().perform()
            XCTAssertTrue(player.playCalls.isEmpty)
        }
    }

    func test_pauseAbbayIntent_audioUnavailable_doesNotPause() async throws {
        let book = audio(title: "Book", url: "file:///b.m4b")
        NowPlayingManager.shared.setPlayer(player, currentAudio: book)
        try await withUnavailableFlag {
            _ = try await PauseAbbayIntent().perform()
            XCTAssertEqual(player.pauseCallCount, 0)
        }
    }

    func test_nextChapterIntent_audioUnavailable_doesNotSkip() async throws {
        let book = audio(title: "Book", url: "file:///b.m4b")
        NowPlayingManager.shared.setPlayer(player, currentAudio: book)
        try await withUnavailableFlag {
            _ = try await NextChapterIntent().perform()
            XCTAssertEqual(player.skipNextCallCount, 0)
        }
    }

    func test_previousChapterIntent_audioUnavailable_doesNotSkip() async throws {
        let book = audio(title: "Book", url: "file:///b.m4b")
        NowPlayingManager.shared.setPlayer(player, currentAudio: book)
        try await withUnavailableFlag {
            _ = try await PreviousChapterIntent().perform()
            XCTAssertEqual(player.skipPreviousCallCount, 0)
        }
    }

    func test_playBookByNameIntent_audioUnavailable_doesNotPlay() async throws {
        let url = try XCTUnwrap(URL(string: "file:///hp.m4b"))
        let book = audio(title: "Harry Potter", url: url.absoluteString)
        lister.stub = [book]
        loader.stubs[url.absoluteString] = book

        try await withUnavailableFlag {
            var intent = PlayBookByNameIntent()
            intent.bookName = "Harry Potter"
            _ = try await intent.perform()
            XCTAssertEqual(player.playCalls.count, 0)
        }
    }
}
