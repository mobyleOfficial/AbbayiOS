//
//  SiriEntityTests.swift
//  AbbayTests
//

@testable import Abbay
import AppIntents
import XCTest

/// Covers the entity-parameter path that makes one-shot phrases possible:
/// "Play <title> in Abbay" and "Play chapter 4 in Abbay".
final class SiriEntityTests: XCTestCase {
    private var player = MockPlayer()
    private var loader = MockLoadAudioUseCase()
    private var lister = MockLoadAllAudiosUseCase()
    /// The container's in-memory App Group store, and the last-played store over it.
    private var appGroup = InMemoryKeyValueStore()
    private var lastPlayed = LastPlayedStore(store: InMemoryKeyValueStore(), legacyStore: InMemoryKeyValueStore())

    override func setUpWithError() throws {
        try super.setUpWithError()
        player = MockPlayer()
        loader = MockLoadAudioUseCase()
        lister = MockLoadAllAudiosUseCase()
        appGroup = InMemoryKeyValueStore()
        let container = MockDependencyContainer(
            player: player,
            loadAudio: loader,
            loadAllAudios: lister,
            appGroup: appGroup
        )
        lastPlayed = container.lastPlayed
        DependencyContainer.configure(with: container)
    }

    override func tearDownWithError() throws {
        DependencyContainer.reset()
        NowPlayingManager.shared.setPlayer(player, currentAudio: nil)
        try super.tearDownWithError()
    }

    private func audio(
        title: String,
        url: String,
        chapters: [ChapterModel] = []
    ) -> AudioModel {
        var model = AudioModel()
        model.title = title
        model.url = URL(string: url)
        model.chapters = chapters
        return model
    }

    private func chapters(_ starts: [Double]) -> [ChapterModel] {
        starts.enumerated().map { index, start in
            var chapter = ChapterModel()
            chapter.title = "Chapter \(index + 1)"
            chapter.startTime = start
            chapter.duration = 100
            return chapter
        }
    }

    // MARK: - AudiobookEntityQuery

    func test_audiobookQuery_matching_resolvesPartialSpokenTitle() async throws {
        lister.stub = [
            audio(title: "Harry Potter and the Goblet of Fire", url: "file:///gof"),
            audio(title: "The Hobbit", url: "file:///hobbit")
        ]
        let results = try await AudiobookEntityQuery().entities(matching: "goblet of fire")
        XCTAssertEqual(results.map(\.id), ["file:///gof"])
    }

    func test_audiobookQuery_matching_unknownTitle_returnsEmpty() async throws {
        lister.stub = [audio(title: "The Hobbit", url: "file:///hobbit")]
        let results = try await AudiobookEntityQuery().entities(matching: "Dune")
        XCTAssertTrue(results.isEmpty)
    }

    func test_audiobookQuery_suggested_putsLastPlayedFirst() async throws {
        lister.stub = [
            audio(title: "First", url: "file:///first"),
            audio(title: "Second", url: "file:///second")
        ]
        lastPlayed.save(url: try XCTUnwrap(URL(string: "file:///second")))
        let results = try await AudiobookEntityQuery().suggestedEntities()
        XCTAssertEqual(results.map(\.id), ["file:///second", "file:///first"])
    }

    func test_audiobookQuery_suggested_respectsPhraseBudgetCap() async throws {
        lister.stub = (0..<(AudiobookEntityQuery.suggestionLimit + 5)).map {
            audio(title: "Book \($0)", url: "file:///book\($0)")
        }
        let results = try await AudiobookEntityQuery().suggestedEntities()
        XCTAssertEqual(results.count, AudiobookEntityQuery.suggestionLimit)
    }

    func test_audiobookQuery_entitiesForIdentifiers_filtersToRequested() async throws {
        lister.stub = [
            audio(title: "First", url: "file:///first"),
            audio(title: "Second", url: "file:///second")
        ]
        let results = try await AudiobookEntityQuery().entities(for: ["file:///second"])
        XCTAssertEqual(results.map(\.title), ["Second"])
    }

    func test_audiobookLibrary_fallsBackToSnapshotWhenCoreDataEmpty() throws {
        lister.stub = []
        let snapshot = LibrarySnapshot(
            version: 1,
            updatedAt: Date(),
            audios: [LibrarySnapshotEntry(title: "Snapshot Book", urlString: "file:///snap", bookmarkData: nil)]
        )
        appGroup.set(try JSONEncoder().encode(snapshot), forKey: LibrarySnapshotWriter.key)
        XCTAssertEqual(AudiobookLibrary.all().map(\.title), ["Snapshot Book"])
    }

    // MARK: - ChapterEntityQuery

    func test_chapterQuery_matching_spokenNumberMapsToZeroBasedIndex() async throws {
        let book = audio(title: "Book", url: "file:///b", chapters: chapters([0, 100, 200, 300]))
        NowPlayingManager.shared.setPlayer(player, currentAudio: book)
        let results = try await ChapterEntityQuery().entities(matching: "chapter 4")
        XCTAssertEqual(results.map(\.id), [3])
        XCTAssertEqual(results.map(\.number), [4])
    }

    func test_chapterQuery_matching_numberBeyondBook_returnsEmpty() async throws {
        let book = audio(title: "Book", url: "file:///b", chapters: chapters([0, 100]))
        NowPlayingManager.shared.setPlayer(player, currentAudio: book)
        let results = try await ChapterEntityQuery().entities(matching: "9")
        XCTAssertTrue(results.isEmpty)
    }

    /// The chapter's own title, said with extra words, folded and in either language (#206).
    func test_chapterQuery_matching_titleWithExtraWords_andSpelledNumbers() async throws {
        var titled = chapters([0, 100, 200, 300])
        titled[0].title = "Prólogo"
        titled[1].title = "The Vanishing Glass"
        titled[2].title = "Diagon Alley"
        titled[3].title = "Epilogue"
        let book = audio(title: "Book", url: "file:///b", chapters: titled)
        NowPlayingManager.shared.setPlayer(player, currentAudio: book)
        let query = ChapterEntityQuery()
        // The chapter numbers count from the first chapter after the prologue (#212).
        let cases: [(String, [Int])] = [
            ("o capítulo prologo", [0]),
            ("the prologo chapter", [0]),
            ("vanishing glass", [1]),
            ("chapter one", [1]),
            ("chapter two", [2]),
            ("o segundo capítulo", [2]),
            ("capítulo 3", []),
            ("chapter", []),
            ("the half blood prince", [])
        ]
        for (spoken, ids) in cases {
            let found = try await query.entities(matching: spoken)
            XCTAssertEqual(found.map(\.id), ids, spoken)
        }
    }

    /// The suggestions are what "Play <chapter> in Abbay" expands to: the prologue by its title,
    /// then Chapter 1 (#212).
    func test_chapterQuery_suggested_numbersFromTheFirstChapterAfterThePrologue() async throws {
        var titled = chapters([0, 100, 200, 300])
        titled[0].title = "Prologue"
        titled[1].title = "Chapter 1"
        titled[2].title = "Chapter 2"
        titled[3].title = "Epílogo"
        NowPlayingManager.shared.setPlayer(player, currentAudio: audio(title: "Book", url: "file:///b", chapters: titled))
        let results = try await ChapterEntityQuery().suggestedEntities()
        XCTAssertEqual(results.map(\.number), [nil, 1, 2, nil])
        XCTAssertEqual(
            results.map { $0.displayRepresentation.title.resolved(in: "en") },
            ["Prologue", "Chapter 1", "Chapter 2", "Epílogo"]
        )
        XCTAssertEqual(results[1].displayRepresentation.title.resolved(in: "pt-BR"), "Capítulo 1")
        let byID = try await ChapterEntityQuery().entities(for: [1, 0, 9])
        XCTAssertEqual(byID.map(\.number), [1, nil])
    }

    func test_chapterQuery_suggested_usesLastPlayedBookWhenNothingLoaded() async throws {
        let url = try XCTUnwrap(URL(string: "file:///b"))
        let book = audio(title: "Book", url: url.absoluteString, chapters: chapters([0, 100, 200]))
        loader.stubs[url.absoluteString] = book
        lastPlayed.save(url: url)
        let results = try await ChapterEntityQuery().suggestedEntities()
        XCTAssertEqual(results.map(\.number), [1, 2, 3])
    }

    func test_chapterQuery_suggested_noBook_returnsEmpty() async throws {
        let results = try await ChapterEntityQuery().suggestedEntities()
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - PlayAudiobookIntent

    func test_playAudiobookIntent_reachableBook_plays() async throws {
        let url = try XCTUnwrap(URL(string: "file:///gof"))
        let book = audio(title: "Goblet of Fire", url: url.absoluteString)
        loader.stubs[url.absoluteString] = book

        var intent = PlayAudiobookIntent()
        intent.audiobook = AudiobookEntity(id: url.absoluteString, title: "Goblet of Fire")
        _ = try await intent.perform()

        XCTAssertEqual(player.playCalls.map(\.title), ["Goblet of Fire"])
    }

    func test_playAudiobookIntent_unreachableBook_doesNotPlay() async throws {
        var intent = PlayAudiobookIntent()
        intent.audiobook = AudiobookEntity(id: "file:///gone", title: "Gone")
        _ = try await intent.perform()

        XCTAssertTrue(player.playCalls.isEmpty)
    }

    func test_playAudiobookIntent_unreachableAndLastPlayed_clearsStore() async throws {
        let url = try XCTUnwrap(URL(string: "file:///gone"))
        lastPlayed.save(url: url)

        var intent = PlayAudiobookIntent()
        intent.audiobook = AudiobookEntity(id: url.absoluteString, title: "Gone")
        _ = try await intent.perform()

        XCTAssertNil(lastPlayed.lastPlayedURL())
    }

    func test_playAudiobookIntent_dialogConstantsMatchSpec() {
        XCTAssertEqual(
            PlayAudiobookIntent.cannotFindDialog.resolved(in: "en"),
            "Cannot find that audiobook. It may have been removed or is not downloaded."
        )
        XCTAssertEqual(PlayAudiobookIntent.playingDialog(title: "Foo").resolved(in: "en"), "Playing Foo.")
    }

    func test_playAudiobookIntent_dialogConstants_inPortuguese() {
        XCTAssertEqual(
            PlayAudiobookIntent.cannotFindDialog.resolved(in: "pt-BR"),
            "Não encontrei esse audiolivro. Ele pode ter sido removido ou não estar baixado."
        )
        XCTAssertEqual(PlayAudiobookIntent.playingDialog(title: "Foo").resolved(in: "pt-BR"), "Tocando Foo.")
    }

    // MARK: - PlayChapterIntent

    func test_playChapterIntent_whilePlaying_seeksWithoutReloading() async throws {
        let book = audio(title: "Book", url: "file:///b", chapters: chapters([0, 100, 200, 300]))
        NowPlayingManager.shared.setPlayer(player, currentAudio: book)

        var intent = PlayChapterIntent()
        intent.chapter = ChapterEntity(id: 3)
        _ = try await intent.perform()

        XCTAssertEqual(player.playChapterCalls, [3])
        XCTAssertTrue(player.playCalls.isEmpty)
    }

    func test_playChapterIntent_cold_resumesLastPlayedAtChapterStart() async throws {
        let url = try XCTUnwrap(URL(string: "file:///b"))
        let book = audio(title: "Book", url: url.absoluteString, chapters: chapters([0, 100, 200, 300]))
        loader.stubs[url.absoluteString] = book
        lastPlayed.save(url: url)

        var intent = PlayChapterIntent()
        intent.chapter = ChapterEntity(id: 2)
        _ = try await intent.perform()

        XCTAssertEqual(player.playCalls.count, 1)
        // Position is set before play so the seek cannot race AVPlayerItem loading.
        XCTAssertEqual(player.playCalls.first?.currentTime, 200)
    }

    func test_playChapterIntent_cold_chapterOutOfRange_doesNotPlay() async throws {
        let url = try XCTUnwrap(URL(string: "file:///b"))
        let book = audio(title: "Book", url: url.absoluteString, chapters: chapters([0, 100]))
        loader.stubs[url.absoluteString] = book
        lastPlayed.save(url: url)

        var intent = PlayChapterIntent()
        intent.chapter = ChapterEntity(id: 7)
        _ = try await intent.perform()

        XCTAssertTrue(player.playCalls.isEmpty)
    }

    func test_playChapterIntent_noBookAtAll_doesNotPlay() async throws {
        var intent = PlayChapterIntent()
        intent.chapter = ChapterEntity(id: 0)
        _ = try await intent.perform()

        XCTAssertTrue(player.playCalls.isEmpty)
        XCTAssertTrue(player.playChapterCalls.isEmpty)
    }

    func test_playChapterIntent_dialogConstantsMatchSpec() {
        XCTAssertEqual(
            PlayChapterIntent.nothingToPlayDialog.resolved(in: "en"),
            "Nothing to play. Say 'Play in Abbay' to start a book."
        )
        XCTAssertEqual(
            PlayChapterIntent.noChapterDialog(9).resolved(in: "en"),
            "That audiobook doesn't have a chapter 9."
        )
        XCTAssertEqual(PlayChapterIntent.playingChapterDialog(4).resolved(in: "en"), "Playing chapter 4.")
    }

    func test_playChapterIntent_dialogConstants_inPortuguese() {
        XCTAssertEqual(
            PlayChapterIntent.nothingToPlayDialog.resolved(in: "pt-BR"),
            "Nada para tocar. Diga 'Tocar no Abbay' para começar um livro."
        )
        XCTAssertEqual(
            PlayChapterIntent.noChapterDialog(9).resolved(in: "pt-BR"),
            "Esse audiolivro não tem o capítulo 9."
        )
        XCTAssertEqual(PlayChapterIntent.playingChapterDialog(4).resolved(in: "pt-BR"), "Tocando o capítulo 4.")
    }

    /// A chapter says its own number back, and front matter its title (#212).
    func test_playChapterIntent_dialog_saysTheChaptersNumberOrTitle() {
        var intent = PlayChapterIntent()
        intent.chapter = ChapterEntity(id: 1, number: 1, title: "Chapter 1")
        XCTAssertEqual(intent.playingDialog.resolved(in: "en"), "Playing chapter 1.")
        intent.chapter = ChapterEntity(id: 0, number: nil, title: "Prólogo")
        XCTAssertEqual(intent.playingDialog.resolved(in: "en"), "Playing Prólogo.")
        XCTAssertEqual(intent.playingDialog.resolved(in: "pt-BR"), "Tocando Prólogo.")
    }

    /// Siri shows, and reads back, a chapter by its display representation.
    func test_chapterEntity_displayRepresentation_isLocalized() {
        let title = ChapterEntity(id: 3).displayRepresentation.title
        XCTAssertEqual(title.resolved(in: "en"), "Chapter 4")
        XCTAssertEqual(title.resolved(in: "pt-BR"), "Capítulo 4")
    }
}
