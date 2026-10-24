//
//  CarPlaySceneDelegateTests.swift
//  AbbayTests
//

@testable import Abbay
import CarPlay
import Combine
import XCTest

/// CarPlay was the least-tested surface in the app and the only one with a user-reported total
/// failure (#90). It is also the hardest to reach: there is no first-party automation for
/// `CPTemplate`, and `CPInterfaceController` has no public initialiser, so `didConnect` cannot
/// be driven from a test.
///
/// What *is* reachable is the template-building and observation logic, now that the delegate
/// resolves its dependencies through injectable seams (#96). That is where the open CarPlay
/// defects live.
final class CarPlaySceneDelegateTests: XCTestCase {
    private var player = MockPlayer()
    private var loadAudio = MockLoadAudioUseCase()
    private var loadAll = MockLoadAllAudiosUseCase()
    private var observer = MockPlayerObserver()
    private var libraryChanges = PassthroughSubject<Void, Never>()

    override func setUpWithError() throws {
        try super.setUpWithError()
        player = MockPlayer()
        loadAudio = MockLoadAudioUseCase()
        loadAll = MockLoadAllAudiosUseCase()
        observer = MockPlayerObserver()
        observer.player = player
        libraryChanges = PassthroughSubject<Void, Never>()
        DependencyContainer.configure(
            with: MockDependencyContainer(player: player, loadAudio: loadAudio, loadAllAudios: loadAll)
        )
    }

    override func tearDownWithError() throws {
        DependencyContainer.reset()
        try super.tearDownWithError()
    }

    /// Fully injected: nothing reaches the real container or Core Data.
    private func makeDelegate() -> CarPlaySceneDelegate {
        let delegate = CarPlaySceneDelegate()
        delegate.loadAllAudiosUseCase = loadAll
        delegate.loadAudioUseCase = loadAudio
        delegate.playerObserver = observer
        delegate.libraryChanges = libraryChanges.eraseToAnyPublisher()
        return delegate
    }

    private func book(
        title: String = "Book",
        artist: String = "",
        album: String = "Album",
        duration: Double = 400,
        currentTime: Double = 0,
        chapters: [ChapterModel] = [],
        url: String = "file:///carplay/book.m4b"
    ) -> AudioModel {
        AudioModel(
            title: title,
            albumName: album,
            artist: artist,
            duration: duration,
            currentTime: currentTime,
            chapters: chapters,
            url: URL(string: url)
        )
    }

    private func items(of template: CPListTemplate) -> [CPListItem] {
        template.sections.flatMap { $0.items }.compactMap { $0 as? CPListItem }
    }

    // MARK: - Dependency resolution (#96)

    /// The point of #96: CarPlay shares the app's player and use cases instead of constructing
    /// its own, so playback started in the car is the same session the phone UI sees.
    func test_defaultDependenciesResolveFromTheContainer() {
        let delegate = CarPlaySceneDelegate()

        XCTAssertTrue(
            delegate.loadAllAudiosUseCase as AnyObject === loadAll as AnyObject,
            "loadAllAudios must come from DependencyContainer, not a fresh LoadAllAudiosUseCase"
        )
        XCTAssertTrue(delegate.loadAudioUseCase as AnyObject === loadAudio as AnyObject)
        XCTAssertTrue(
            delegate.playerObserver.player as AnyObject === player as AnyObject,
            "CarPlay must observe the shared player"
        )
    }

    // MARK: - Library template

    func test_buildLibraryTemplate_onePerAudioInStoreOrder() {
        loadAll.stub = [book(title: "One", url: "file:///1.m4b"), book(title: "Two", url: "file:///2.m4b")]
        let delegate = makeDelegate()

        let template = delegate.buildLibraryTemplate()

        XCTAssertEqual(items(of: template).map(\.text), ["One", "Two"])
    }

    func test_buildLibraryTemplate_cachesAudioItemsForLaterLookup() {
        loadAll.stub = [book(title: "One"), book(title: "Two", url: "file:///2.m4b")]
        let delegate = makeDelegate()

        _ = delegate.buildLibraryTemplate()

        XCTAssertEqual(delegate.audioItems.count, 2, "didConnect resolves currentAudio against this")
    }

    func test_buildLibraryTemplate_emptyLibraryStillProducesATemplate() {
        loadAll.stub = []
        let delegate = makeDelegate()

        let template = delegate.buildLibraryTemplate()

        XCTAssertTrue(items(of: template).isEmpty)
        XCTAssertTrue(delegate.audioItems.isEmpty)
    }

    // MARK: - List item

    func test_buildListItem_prefersArtistForDetailText() {
        let delegate = makeDelegate()

        let item = delegate.buildListItem(for: book(artist: "Author", album: "Album"))

        XCTAssertEqual(item.detailText, "Author")
    }

    func test_buildListItem_fallsBackToAlbumWhenArtistIsEmpty() {
        let delegate = makeDelegate()

        let item = delegate.buildListItem(for: book(artist: "", album: "Album"))

        XCTAssertEqual(item.detailText, "Album")
    }

    func test_buildListItem_showsSavedPositionAsProgress() {
        let delegate = makeDelegate()

        let item = delegate.buildListItem(for: book(duration: 400, currentTime: 100))

        XCTAssertEqual(item.playbackProgress, 0.25, accuracy: 0.001)
    }

    func test_buildListItem_zeroDurationLeavesProgressAtZero() {
        let delegate = makeDelegate()

        let item = delegate.buildListItem(for: book(duration: 0, currentTime: 50))

        XCTAssertEqual(item.playbackProgress, 0, "must not divide by a zero duration")
    }

    func test_buildListItem_tracksTheRowWhoseBookIsLoaded() {
        player.url = URL(string: "file:///carplay/book.m4b")
        let delegate = makeDelegate()

        let item = delegate.buildListItem(for: book(url: "file:///carplay/book.m4b"))

        XCTAssertTrue(delegate.currentPlayingItem === item)
    }

    func test_buildListItem_doesNotTrackARowForADifferentBook() {
        player.url = URL(string: "file:///carplay/other.m4b")
        let delegate = makeDelegate()

        _ = delegate.buildListItem(for: book(url: "file:///carplay/book.m4b"))

        XCTAssertNil(delegate.currentPlayingItem)
    }

    // MARK: - Selection

    /// The re-fetch exists so a book resumes from the position the phone last saved, rather than
    /// whatever was cached when the list was built.
    func test_handleAudioSelection_playsTheFreshlyStoredModel() throws {
        let url = try XCTUnwrap(URL(string: "file:///carplay/book.m4b"))
        loadAudio.stubs[url.absoluteString] = book(currentTime: 250)
        let delegate = makeDelegate()

        delegate.handleAudioSelection(book(currentTime: 0))

        XCTAssertEqual(player.playCalls.count, 1)
        XCTAssertEqual(player.playCalls.first?.currentTime, 250, "must play the stored position")
    }

    /// #95: a store miss means the book was deleted on the phone after the list was built.
    /// Playing the listed copy hands `Player.play` a dead URL whose bookmark no longer resolves.
    func test_handleAudioSelection_doesNotPlayABookThatIsNoLongerStored() {
        let delegate = makeDelegate()

        delegate.handleAudioSelection(book(title: "Deleted On Phone", currentTime: 10))

        XCTAssertTrue(player.playCalls.isEmpty, "must not fall back to the stale listed model")
    }

    /// The tapped row is stale, so the list is rebuilt to drop it.
    func test_handleAudioSelection_storeMissRefreshesTheList() {
        let kept = book(title: "Kept", url: "file:///kept.m4b")
        let deleted = book(title: "Deleted", url: "file:///deleted.m4b")
        loadAll.stub = [kept, deleted]
        let delegate = makeDelegate()
        let template = delegate.buildLibraryTemplate()
        loadAll.stub = [kept]

        delegate.handleAudioSelection(deleted)

        XCTAssertEqual(items(of: template).map(\.text), ["Kept"])
    }

    /// Tapping a vanished row must not claim it as the live-progress row, nor release the row of
    /// the book that is still playing.
    func test_rowHandler_vanishedBookLeavesTheTrackedRowAlone() throws {
        let playing = book(title: "Playing", duration: 400, url: "file:///playing.m4b")
        let deleted = book(title: "Deleted", url: "file:///deleted.m4b")
        loadAll.stub = [playing, deleted]
        loadAudio.stubs["file:///playing.m4b"] = playing
        player.url = playing.url
        let delegate = makeDelegate()
        let rows = items(of: delegate.buildLibraryTemplate())
        loadAll.stub = [playing]

        let handler = try XCTUnwrap(rows[1].handler)
        let done = expectation(description: "handler completes")
        handler(rows[1]) { done.fulfill() }
        wait(for: [done], timeout: 1)

        XCTAssertEqual(delegate.currentPlayingURL, playing.url)
        XCTAssertTrue(player.playCalls.isEmpty)
    }

    func test_rowHandler_playsAndTracksAStoredBook() throws {
        let stored = book(title: "Stored", currentTime: 40, url: "file:///stored.m4b")
        loadAll.stub = [stored]
        loadAudio.stubs["file:///stored.m4b"] = stored
        let delegate = makeDelegate()
        let rows = items(of: delegate.buildLibraryTemplate())

        let handler = try XCTUnwrap(rows[0].handler)
        handler(rows[0]) {}

        XCTAssertEqual(player.playCalls.map(\.title), ["Stored"])
        XCTAssertTrue(delegate.currentPlayingItem === rows[0])
    }

    // MARK: - Chapter list

    func test_buildChapterListTemplate_onePerChapter() {
        let delegate = makeDelegate()
        let chapters = [
            ChapterModel(title: "One", startTime: 0, duration: 100),
            ChapterModel(title: "Two", startTime: 100, duration: 100)
        ]

        let template = delegate.buildChapterListTemplate(for: book(chapters: chapters))

        XCTAssertEqual(items(of: template).map(\.text), ["One", "Two"])
    }

    func test_buildChapterListTemplate_noChaptersProducesAnEmptyList() {
        let delegate = makeDelegate()

        let template = delegate.buildChapterListTemplate(for: book(chapters: []))

        XCTAssertTrue(items(of: template).isEmpty)
    }

    // MARK: - Observation

    func test_setupObservers_playbackElsewhereUpdatesCurrentAudio() {
        let delegate = makeDelegate()
        delegate.setupObservers()

        observer.emitPlayUrl(book(title: "Started By Siri"))

        XCTAssertEqual(delegate.currentAudio?.title, "Started By Siri")
    }

    func test_setupObservers_timeUpdatesDriveTheTrackedRowsProgress() {
        player.url = URL(string: "file:///carplay/book.m4b")
        let delegate = makeDelegate()
        let item = delegate.buildListItem(for: book(duration: 400))
        delegate.setupObservers()
        observer.emitPlayUrl(book(duration: 400))

        observer.emitTime(200)

        XCTAssertEqual(item.playbackProgress, 0.5, accuracy: 0.001)
    }

    /// #92: progress is computed from `currentAudio` but written to `currentPlayingItem`, and
    /// the two are updated by different paths. Start book A from CarPlay, then start book B from
    /// the phone or Siri, and A's row animates with B's position -- at B's ratio.
    func test_playbackSwitchingToAnotherBook_movesProgressToThatBooksRow() {
        let bookA = book(title: "A", duration: 400, url: "file:///a.m4b")
        let bookB = book(title: "B", duration: 100, url: "file:///b.m4b")
        loadAll.stub = [bookA, bookB]
        player.url = bookA.url
        let delegate = makeDelegate()
        let template = delegate.buildLibraryTemplate()
        let rows = items(of: template)
        delegate.setupObservers()
        observer.emitPlayUrl(bookA)

        // Book B takes over from outside CarPlay.
        observer.emitPlayUrl(bookB)
        observer.emitTime(50)

        XCTAssertEqual(
            rows[1].playbackProgress,
            0.5,
            accuracy: 0.001,
            "B's row should show B's position"
        )
        XCTAssertNotEqual(
            rows[0].playbackProgress,
            0.5,
            accuracy: 0.001,
            "A's row must not animate with B's playback"
        )
    }

    /// The row being left behind must go back to its own saved position rather than keeping the
    /// last live value it was given while it was the tracked row.
    func test_playbackSwitchingAway_restoresTheOldRowsStoredProgress() {
        let bookA = book(title: "A", duration: 400, currentTime: 100, url: "file:///a.m4b")
        let bookB = book(title: "B", duration: 100, url: "file:///b.m4b")
        loadAll.stub = [bookA, bookB]
        player.url = bookA.url
        let delegate = makeDelegate()
        let rows = items(of: delegate.buildLibraryTemplate())
        delegate.setupObservers()
        observer.emitPlayUrl(bookA)
        observer.emitTime(300)
        XCTAssertEqual(rows[0].playbackProgress, 0.75, accuracy: 0.001)

        observer.emitPlayUrl(bookB)

        XCTAssertEqual(
            rows[0].playbackProgress,
            0.25,
            accuracy: 0.001,
            "A's row should fall back to its stored 100/400, not keep the live 300/400"
        )
    }

    func test_trackRow_unknownBookClearsTheTrackedRow() {
        loadAll.stub = [book(title: "A", url: "file:///a.m4b")]
        player.url = URL(string: "file:///a.m4b")
        let delegate = makeDelegate()
        _ = delegate.buildLibraryTemplate()
        XCTAssertNotNil(delegate.currentPlayingItem)

        delegate.trackRow(for: book(title: "Not Listed", url: "file:///elsewhere.m4b"))

        XCTAssertNil(delegate.currentPlayingItem, "no row exists for a book outside the list")
    }

    func test_setupObservers_timeUpdatesAreIgnoredWithoutALoadedBook() {
        player.url = URL(string: "file:///carplay/book.m4b")
        let delegate = makeDelegate()
        let item = delegate.buildListItem(for: book(duration: 400, currentTime: 0))
        delegate.setupObservers()

        observer.emitTime(200)

        XCTAssertEqual(item.playbackProgress, 0, "no currentAudio yet, so there is nothing to scale by")
    }
}
