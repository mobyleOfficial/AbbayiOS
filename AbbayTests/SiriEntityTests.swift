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
    private let suiteName = "abbay.tests.SiriEntityTests"

    override func setUpWithError() throws {
        try super.setUpWithError()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        LastPlayedStore.defaults = defaults
        LastPlayedStore.standardFallback = defaults
        LibrarySnapshotReader.defaults = defaults

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
        LastPlayedStore.defaults = AppGroup.defaults
        LastPlayedStore.standardFallback = .standard
        LibrarySnapshotReader.defaults = AppGroup.defaults
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
        LastPlayedStore.save(url: try XCTUnwrap(URL(string: "file:///second")))
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
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let snapshot = LibrarySnapshot(
            version: 1,
            updatedAt: Date(),
            audios: [LibrarySnapshotEntry(title: "Snapshot Book", urlString: "file:///snap", bookmarkData: nil)]
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: LibrarySnapshotWriter.key)
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

    func test_chapterQuery_suggested_usesLastPlayedBookWhenNothingLoaded() async throws {
        let url = try XCTUnwrap(URL(string: "file:///b"))
        let book = audio(title: "Book", url: url.absoluteString, chapters: chapters([0, 100, 200]))
        loader.stubs[url.absoluteString] = book
        LastPlayedStore.save(url: url)
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
        LastPlayedStore.save(url: url)

        var intent = PlayAudiobookIntent()
        intent.audiobook = AudiobookEntity(id: url.absoluteString, title: "Gone")
        _ = try await intent.perform()

        XCTAssertNil(LastPlayedStore.lastPlayedURL())
    }

    func test_playAudiobookIntent_dialogConstantsMatchSpec() {
        XCTAssertEqual(
            PlayAudiobookIntent.cannotFindDialog,
            "Cannot find that audiobook. It may have been removed or is not downloaded."
        )
        XCTAssertEqual(PlayAudiobookIntent.playingDialog(title: "Foo"), "Playing Foo.")
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
        LastPlayedStore.save(url: url)

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
        LastPlayedStore.save(url: url)

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
            PlayChapterIntent.nothingToPlayDialog,
            "Nothing to play. Say 'Play in Abbay' to start a book."
        )
        XCTAssertEqual(PlayChapterIntent.noChapterDialog(9), "That audiobook doesn't have a chapter 9.")
        XCTAssertEqual(PlayChapterIntent.playingChapterDialog(4), "Playing chapter 4.")
    }
}
