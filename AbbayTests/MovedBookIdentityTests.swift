//
//  MovedBookIdentityTests.swift
//  AbbayTests
//

@testable import Abbay
import AppIntents
import CarPlay
import Combine
import CoreData
import Intents
import XCTest

/// #186: a book whose bookmark resolves somewhere other than the URL its row was saved under (the
/// file moved in Files, an iCloud re-sync, a reinstall that moved the bundle). #176 made the row
/// writes find it; every other lookup must too. A book has one identity, its row's URL: last
/// played, the Siri snapshot and entity ids, speeds, CarPlay's playing row and the playback
/// center all key it by that. Only opening the file uses where the bookmark resolves now.
///
/// The resolver is stubbed (a moved file can't be made on demand); the rows are real Core Data.
final class MovedBookIdentityTests: XCTestCase {
    private let storedURL = URL(fileURLWithPath: "/moved-book-identity-tests/book.m4b")
    /// Where the bookmark resolves to now.
    private let movedURL = URL(fileURLWithPath: "/moved-book-identity-tests/moved/book.m4b")
    private let bookmark = Data([9, 8, 7])
    private var appGroup = InMemoryKeyValueStore()
    private var settings = AppSettings(store: InMemoryKeyValueStore())

    override func setUpWithError() throws {
        try super.setUpWithError()
        appGroup = InMemoryKeyValueStore()
        settings = AppSettings(store: InMemoryKeyValueStore())
        removeBooks()
        try insertBook()
    }

    override func tearDown() {
        DependencyContainer.reset()
        NowPlayingManager.shared.clearNowPlaying()
        removeBooks()
        super.tearDown()
    }

    // MARK: - The model

    func test_load_movedBook_isIdentifiedByItsRow_andOpensWhereTheFileIsNow() throws {
        let book = try loadMovedBook()

        XCTAssertEqual(book.url, storedURL, "the identity every store keys the book by")
        XCTAssertEqual(book.fileURL, movedURL, "what the player opens")
    }

    func test_loadAll_movedBook_isIdentifiedByItsRow() throws {
        let book = try XCTUnwrap(loadAll().first { $0.title == "Moved Book" })

        XCTAssertEqual(book.url, storedURL)
        XCTAssertEqual(book.fileURL, movedURL)
    }

    func test_newBook_opensItsOwnURL() {
        let book = AudioModel(url: movedURL)

        XCTAssertEqual(book.fileURL, movedURL)
    }

    // MARK: - Player

    func test_play_movedBook_opensTheFileWhereItIsNow() throws {
        let player = makePlayer()
        var book = try loadMovedBook()

        player.play(&book)

        XCTAssertEqual(player.currentItemURL, movedURL)
        XCTAssertEqual(player.url, storedURL, "the loaded book is identified by its row")
    }

    func test_play_movedBook_savesLastPlayedUnderItsRow() throws {
        let player = makePlayer()
        var book = try loadMovedBook()

        player.play(&book)

        XCTAssertEqual(LastPlayedStore.inMemory(appGroup).lastPlayedURL(), storedURL)
    }

    func test_speed_movedBook_isKeptUnderItsRow() throws {
        let player = makePlayer()
        var book = try loadMovedBook()
        player.play(&book)

        player.setPlaybackRate(1.5)

        XCTAssertEqual(settings.playbackSpeed(for: storedURL), 1.5)
        let next = makePlayer()
        var again = try loadMovedBook()
        next.play(&again)
        XCTAssertEqual(next.playbackRate, 1.5, "the speed survives the next load")
    }

    // MARK: - Siri

    func test_resume_movedBook_findsIt() async throws {
        let player = makePlayer()
        var book = try loadMovedBook()
        player.play(&book)
        let mock = configureContainer()

        _ = try await ResumeAbbayIntent().perform()

        XCTAssertEqual(mock.playCalls.map(\.title), ["Moved Book"])
        XCTAssertEqual(mock.playCalls.first?.fileURL, movedURL)
    }

    func test_snapshot_movedBook_publishesItsRowURL() throws {
        try writeSnapshot()

        let entry = try XCTUnwrap(LibrarySnapshotReader(store: appGroup).read().first { $0.title == "Moved Book" })
        XCTAssertEqual(entry.urlString, storedURL.absoluteString)
    }

    func test_entityQuery_movedBook_findsItByTheIdItPublished() async throws {
        let mock = configureContainer()
        let suggested = try await AudiobookEntityQuery().suggestedEntities()
        let entity = try XCTUnwrap(suggested.first { $0.title == "Moved Book" })

        let found = try await AudiobookEntityQuery().entities(for: [entity.id])
        var intent = PlayAudiobookIntent()
        intent.audiobook = try XCTUnwrap(found.first)
        _ = try await intent.perform()

        XCTAssertEqual(mock.playCalls.map(\.title), ["Moved Book"])
    }

    func test_playByName_movedBook_playsIt() async throws {
        let mock = configureContainer()
        var intent = PlayBookByNameIntent()
        intent.bookName = "Moved Book"

        _ = try await intent.perform()

        XCTAssertEqual(mock.playCalls.map(\.title), ["Moved Book"])
    }

    func test_inAppPlayMedia_movedBook_playsIt() throws {
        try writeSnapshot()
        let mock = MockPlayer()
        let lastPlayed = LastPlayedStore.inMemory(appGroup)
        let reader = { LibrarySnapshotReader(store: self.appGroup).read() }
        let router = IntentRouter(
            loadAudio: makeLoadAudio(),
            snapshotWriter: MockLibrarySnapshotWriter(),
            snapshotReader: reader,
            player: { mock },
            lastPlayed: lastPlayed,
            launchState: .inMemory(appGroup),
            diagnostics: SiriDiagnostics(store: appGroup)
        )
        let handler = InAppPlayMediaHandler(
            router: router,
            snapshotReader: reader,
            lastPlayed: lastPlayed,
            diagnostics: SiriDiagnostics(store: appGroup)
        )
        let intent = Self.intent(searching: "Moved Book")
        let item = try XCTUnwrap(handler.pick(for: intent))

        let response = router.handle(Self.intent(playing: item))

        XCTAssertEqual(response.code, .success)
        XCTAssertEqual(mock.playCalls.map(\.title), ["Moved Book"])
    }

    /// A donation or a snapshot from before #186 named the book by where its file resolved then.
    func test_router_legacyResolvedIdentifier_stillFindsTheBook() throws {
        let mock = MockPlayer()
        let entry = LibrarySnapshotEntry(
            title: "Moved Book",
            urlString: storedURL.absoluteString,
            bookmarkData: bookmark
        )
        let router = IntentRouter(
            loadAudio: makeLoadAudio(),
            snapshotWriter: MockLibrarySnapshotWriter(),
            snapshotReader: { [entry] },
            player: { mock },
            lastPlayed: .inMemory(appGroup),
            launchState: .inMemory(appGroup),
            diagnostics: SiriDiagnostics(store: appGroup),
            resolveBookmark: moved
        )
        let item = INMediaItem(identifier: movedURL.absoluteString, title: "Moved Book", type: .audioBook, artwork: nil)

        let response = router.handle(Self.intent(playing: item))

        XCTAssertEqual(response.code, .success)
        XCTAssertEqual(mock.playCalls.first?.url, storedURL)
    }

    // MARK: - CarPlay and the app's playback state

    func test_carPlay_marksTheMovedBookPlaying() throws {
        let player = makePlayer()
        var book = try loadMovedBook()
        player.play(&book)
        let observer = MockPlayerObserver()
        observer.player = player
        let delegate = CarPlaySceneDelegate()
        delegate.loadAllAudiosUseCase = makeLoadAll()
        delegate.loadAudioUseCase = makeLoadAudio()
        delegate.playerObserver = observer
        delegate.libraryChanges = Empty().eraseToAnyPublisher()

        let item = delegate.buildListItem(for: try XCTUnwrap(loadAll().first { $0.title == "Moved Book" }))

        XCTAssertTrue(delegate.currentPlayingItem === item)
    }

    @MainActor
    func test_playbackCenter_seedsTheLoadedMovedBookFromTheStore() throws {
        let player = makePlayer()
        var book = try loadMovedBook()
        player.play(&book)

        let center = PlaybackCenter(player: player, loadAudio: makeLoadAudio())

        let loaded = try XCTUnwrap(center.state.loadedBook)
        XCTAssertEqual(loaded.title, "Moved Book", "found by its row, not rebuilt from a bare URL")
    }

    // MARK: - Delete

    func test_delete_movedBook_removesItsRowAndItsSpeed() throws {
        settings.setSpeed(1.5, for: storedURL)
        let book = try loadMovedBook()
        var forgotten: [URL?] = []

        DeleteAudioUseCase(forgetSettings: { forgotten.append($0) }, snapshotWriter: MockLibrarySnapshotWriter())
            .execute(book)

        XCTAssertEqual(rowCount(storedURL), 0)
        XCTAssertEqual(forgotten, [storedURL], "the speed is forgotten under the key it was saved by")
    }

    // MARK: - Helpers

    private func moved(_ data: Data?) -> ResolvedBookmark? {
        guard data == bookmark else { return URL.resolveBookmarkRefreshing(from: data) }
        return ResolvedBookmark(url: movedURL, refreshedData: nil)
    }

    private func noStaleSaves() -> StaleBookmarkSaver {
        StaleBookmarkSaver(save: { MockSaveAudioUseCase() })
    }

    private func makeLoadAudio() -> LoadAudioUseCase {
        LoadAudioUseCase(resolveBookmark: moved, staleBookmarks: noStaleSaves(), movedBooks: noMigration())
    }

    private func makeLoadAll() -> LoadAllAudiosUseCase {
        LoadAllAudiosUseCase(resolveBookmark: moved, staleBookmarks: noStaleSaves(), movedBooks: noMigration())
    }

    private func noMigration() -> MovedBookKeyMigration {
        MovedBookKeyMigration(stores: { nil })
    }

    private func loadMovedBook() throws -> AudioModel {
        try XCTUnwrap(makeLoadAudio().execute(url: storedURL))
    }

    private func loadAll() -> [AudioModel] {
        makeLoadAll().execute()
    }

    private func makePlayer() -> Player {
        Player(
            savePlaybackPositionUseCase: MockSavePlaybackPositionUseCase(),
            intentDonor: MockIntentDonor(),
            librarySnapshotWriter: MockLibrarySnapshotWriter(),
            audioSessionActivator: MockAudioSessionActivator(),
            bookmarkProvider: MockBookmarkProvider(),
            speeds: settings,
            lastPlayed: .inMemory(appGroup),
            launchState: .inMemory()
        )
    }

    /// The container the intents read: the real use cases over the stubbed resolver, a mock player.
    private func configureContainer() -> MockPlayer {
        let mock = MockPlayer()
        DependencyContainer.configure(
            with: MockDependencyContainer(
                player: mock,
                loadAudio: makeLoadAudio(),
                loadAllAudios: makeLoadAll(),
                settings: settings,
                appGroup: appGroup
            )
        )
        return mock
    }

    private func writeSnapshot() throws {
        LibrarySnapshotWriter(store: appGroup, loadAllAudios: makeLoadAll(), publisher: NoopSiriLibraryPublisher())
            .refresh()
    }

    private static func intent(searching name: String) -> INPlayMediaIntent {
        let search = INMediaSearch(
            mediaType: .audioBook,
            sortOrder: .unknown,
            mediaName: name,
            artistName: nil,
            albumName: nil,
            genreNames: nil,
            moodNames: nil,
            releaseDate: nil,
            reference: .unknown,
            mediaIdentifier: nil
        )
        return INPlayMediaIntent(
            mediaItems: nil,
            mediaContainer: nil,
            playShuffled: nil,
            playbackRepeatMode: .none,
            resumePlayback: nil,
            playbackQueueLocation: .now,
            playbackSpeed: nil,
            mediaSearch: search
        )
    }

    private static func intent(playing item: INMediaItem) -> INPlayMediaIntent {
        INPlayMediaIntent(
            mediaItems: [item],
            mediaContainer: nil,
            playShuffled: nil,
            playbackRepeatMode: .none,
            resumePlayback: nil,
            playbackQueueLocation: .now,
            playbackSpeed: nil,
            mediaSearch: nil
        )
    }

    private func insertBook() throws {
        var audio = AudioModel()
        audio.title = "Moved Book"
        audio.duration = 400
        audio.url = storedURL
        audio.bookmarkData = bookmark
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(audio)
    }

    private func rowCount(_ url: URL) -> Int {
        LocalStorage.persistent.performAndWait { context in
            let request = AudioDataModel.fetchRequest()
            request.predicate = NSPredicate(format: "url == %@", url as NSURL)
            return (try? context.count(for: request)) ?? 0
        }
    }

    private func removeBooks() {
        LocalStorage.persistent.performAndWait { context in
            for url in [storedURL, movedURL] {
                let request = AudioDataModel.fetchRequest()
                request.predicate = NSPredicate(format: "url == %@", url as NSURL)
                for book in (try? context.fetch(request)) ?? [] {
                    context.delete(book)
                }
            }
        }
        LocalStorage.persistent.saveContext()
    }
}
