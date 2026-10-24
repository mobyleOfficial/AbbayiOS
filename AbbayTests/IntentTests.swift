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
    /// The container's in-memory App Group stores: what the intents read and write.
    private var lastPlayed = LastPlayedStore(store: InMemoryKeyValueStore(), legacyStore: InMemoryKeyValueStore())
    private var launchState = LaunchStateFlag(store: InMemoryKeyValueStore())

    override func setUpWithError() throws {
        try super.setUpWithError()
        player = MockPlayer()
        loader = MockLoadAudioUseCase()
        lister = MockLoadAllAudiosUseCase()
        let container = MockDependencyContainer(player: player, loadAudio: loader, loadAllAudios: lister)
        lastPlayed = container.lastPlayed
        launchState = container.launchState
        DependencyContainer.configure(with: container)
    }

    override func tearDownWithError() throws {
        DependencyContainer.reset()
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
        XCTAssertEqual(ResumeAbbayIntent.addBookDialog.resolved(in: "en"), "Add a book in Abbay first.")
        XCTAssertEqual(
            ResumeAbbayIntent.cannotFindDialog.resolved(in: "en"),
            "Cannot find that audiobook. It may have been removed or is not downloaded."
        )
        XCTAssertEqual(ResumeAbbayIntent.playingDialog(title: "Foo").resolved(in: "en"), "Playing Foo.")
    }

    func test_resume_dialogConstants_inPortuguese() {
        XCTAssertEqual(ResumeAbbayIntent.addBookDialog.resolved(in: "pt-BR"), "Adicione um livro no Abbay primeiro.")
        XCTAssertEqual(
            ResumeAbbayIntent.cannotFindDialog.resolved(in: "pt-BR"),
            "Não encontrei esse audiolivro. Ele pode ter sido removido ou não estar baixado."
        )
        XCTAssertEqual(ResumeAbbayIntent.playingDialog(title: "Foo").resolved(in: "pt-BR"), "Tocando Foo.")
    }

    func test_resume_noLastPlayed_loaderNotCalledAndPlayerNotCalled() async throws {
        _ = try await ResumeAbbayIntent().perform()
        XCTAssertEqual(loader.executeCalls.count, 0)
        XCTAssertEqual(player.playCalls.count, 0)
    }

    func test_resume_lastPlayedSet_butLoaderReturnsNil_clearsStoreAndDoesNotPlay() async throws {
        let url = try XCTUnwrap(URL(string: "file:///gone.m4b"))
        lastPlayed.save(url: url)
        // loader has no stub for url → returns nil

        _ = try await ResumeAbbayIntent().perform()

        XCTAssertEqual(loader.executeCalls.compactMap { $0 }, [url])
        XCTAssertEqual(player.playCalls.count, 0)
        XCTAssertNil(lastPlayed.lastPlayedURL(), "store must be cleared to avoid stuck loop")
    }

    func test_resume_lastPlayedReachable_playsAndKeepsStore() async throws {
        let url = try XCTUnwrap(URL(string: "file:///book.m4b"))
        let book = audio(title: "My Book", url: url.absoluteString)
        lastPlayed.save(url: url)
        loader.stubs[url.absoluteString] = book

        _ = try await ResumeAbbayIntent().perform()

        XCTAssertEqual(player.playCalls.count, 1)
        XCTAssertEqual(player.playCalls.first?.url, url)
        XCTAssertEqual(lastPlayed.lastPlayedURL(), url)
    }

    // MARK: Pause

    func test_pause_dialogConstants_matchSpecVerbatim() {
        XCTAssertEqual(PauseAbbayIntent.nothingPlayingDialog.resolved(in: "en"), "Nothing is playing.")
        XCTAssertEqual(PauseAbbayIntent.pausedDialog.resolved(in: "en"), "Paused.")
    }

    func test_pause_dialogConstants_inPortuguese() {
        XCTAssertEqual(PauseAbbayIntent.nothingPlayingDialog.resolved(in: "pt-BR"), "Nada está tocando.")
        XCTAssertEqual(PauseAbbayIntent.pausedDialog.resolved(in: "pt-BR"), "Pausado.")
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
            NextChapterIntent.nothingPlayingDialog.resolved(in: "en"),
            "Nothing is playing. Say 'Play in Abbay' to start."
        )
        XCTAssertEqual(NextChapterIntent.nextChapterDialog.resolved(in: "en"), "Next chapter.")
    }

    /// The hint names "Tocar no Abbay", which must stay a registered pt-BR phrase
    /// (pinned in `AppShortcutPhraseTests`).
    func test_nextChapter_dialogConstants_inPortuguese() {
        XCTAssertEqual(
            NextChapterIntent.nothingPlayingDialog.resolved(in: "pt-BR"),
            "Nada está tocando. Diga 'Tocar no Abbay' para começar."
        )
        XCTAssertEqual(NextChapterIntent.nextChapterDialog.resolved(in: "pt-BR"), "Próximo capítulo.")
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
            PreviousChapterIntent.nothingPlayingDialog.resolved(in: "en"),
            "Nothing is playing. Say 'Play in Abbay' to start."
        )
        XCTAssertEqual(PreviousChapterIntent.previousChapterDialog.resolved(in: "en"), "Previous chapter.")
    }

    /// The hint names "Tocar no Abbay", which must stay a registered pt-BR phrase
    /// (pinned in `AppShortcutPhraseTests`).
    func test_previousChapter_dialogConstants_inPortuguese() {
        XCTAssertEqual(
            PreviousChapterIntent.nothingPlayingDialog.resolved(in: "pt-BR"),
            "Nada está tocando. Diga 'Tocar no Abbay' para começar."
        )
        XCTAssertEqual(PreviousChapterIntent.previousChapterDialog.resolved(in: "pt-BR"), "Capítulo anterior.")
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
            PlayBookByNameIntent.noMatchDialog("Foo").resolved(in: "en"),
            "No audiobook matches 'Foo'."
        )
        XCTAssertEqual(
            PlayBookByNameIntent.cannotFindDialog.resolved(in: "en"),
            "Cannot find that audiobook. It may have been removed or is not downloaded."
        )
        XCTAssertEqual(
            PlayBookByNameIntent.playingDialog(title: "Foo").resolved(in: "en"),
            "Playing Foo."
        )
    }

    func test_playByName_dialogConstants_inPortuguese() {
        XCTAssertEqual(
            PlayBookByNameIntent.noMatchDialog("Foo").resolved(in: "pt-BR"),
            "Nenhum audiolivro corresponde a 'Foo'."
        )
        XCTAssertEqual(
            PlayBookByNameIntent.cannotFindDialog.resolved(in: "pt-BR"),
            "Não encontrei esse audiolivro. Ele pode ter sido removido ou não estar baixado."
        )
        XCTAssertEqual(PlayBookByNameIntent.playingDialog(title: "Foo").resolved(in: "pt-BR"), "Tocando Foo.")
    }

    // MARK: Shared

    func test_audioUnavailableDialog_matchesSpecInEnglishAndPortuguese() {
        XCTAssertEqual(
            abbayAudioUnavailableDialog.resolved(in: "en"),
            "Audio temporarily unavailable. Try again in a moment."
        )
        XCTAssertEqual(
            abbayAudioUnavailableDialog.resolved(in: "pt-BR"),
            "Áudio temporariamente indisponível. Tente de novo em instantes."
        )
    }

    /// Titles and the parameter prompt show in Shortcuts and in Siri's UI, so they localize too.
    func test_intentTitlesAndPrompt_areTranslatedToPortuguese() {
        let pairs: [(LocalizedStringResource, String)] = [
            (ResumeAbbayIntent.title, "Tocar no Abbay"),
            (PauseAbbayIntent.title, "Pausar o Abbay"),
            (NextChapterIntent.title, "Próximo capítulo no Abbay"),
            (PreviousChapterIntent.title, "Capítulo anterior no Abbay"),
            (PlayBookByNameIntent.title, "Tocar audiolivro no Abbay"),
            (PlayAudiobookIntent.title, "Tocar audiolivro"),
            (PlayChapterIntent.title, "Tocar capítulo"),
            ("Which audiobook?", "Qual audiolivro?")
        ]
        for (resource, portuguese) in pairs {
            XCTAssertEqual(resource.resolved(in: "pt-BR"), portuguese)
        }
    }

    func test_playByName_noMatch_doesNotPlay_doesNotClearStore() async throws {
        let saved = try XCTUnwrap(URL(string: "file:///saved.m4b"))
        lastPlayed.save(url: saved)
        lister.stub = []  // empty library → fuzzyMatch returns nil

        var intent = PlayBookByNameIntent()
        intent.bookName = "anything"
        _ = try await intent.perform()

        XCTAssertEqual(player.playCalls.count, 0)
        XCTAssertEqual(lastPlayed.lastPlayedURL(), saved, "no-match must not touch the store")
    }

    func test_playByName_unreachable_andIsLastPlayed_clearsStore() async throws {
        let url = try XCTUnwrap(URL(string: "file:///gone.m4b"))
        let book = audio(title: "Gone Book", url: url.absoluteString)
        lister.stub = [book]
        lastPlayed.save(url: url)
        // loader has no stub for url → returns nil (file unreachable)

        var intent = PlayBookByNameIntent()
        intent.bookName = "Gone Book"
        _ = try await intent.perform()

        XCTAssertNil(lastPlayed.lastPlayedURL(), "store must be cleared when the dead match was the saved pointer")
        XCTAssertEqual(player.playCalls.count, 0)
    }

    func test_playByName_unreachable_andNotLastPlayed_doesNotClearStore() async throws {
        let saved = try XCTUnwrap(URL(string: "file:///saved.m4b"))
        let dead = try XCTUnwrap(URL(string: "file:///dead.m4b"))
        let book = audio(title: "Dead Book", url: dead.absoluteString)
        lister.stub = [book]
        lastPlayed.save(url: saved)
        // loader has no stub for dead.absoluteString → returns nil

        var intent = PlayBookByNameIntent()
        intent.bookName = "Dead Book"
        _ = try await intent.perform()

        XCTAssertEqual(
            lastPlayed.lastPlayedURL(),
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
        launchState.markUnavailable()
        // The intents now RETRY activation instead of trusting a stale flag, so the
        // unavailable branch is only reachable when activation itself fails. Stub the
        // activator to throw — the real AVAudioSession always succeeds in the simulator.
        let originalActivator = AudioSessionActivator.makeActivator
        let failing = MockAudioSessionActivator()
        failing.shouldThrow = true
        AudioSessionActivator.makeActivator = { failing }
        defer {
            AudioSessionActivator.makeActivator = originalActivator
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
