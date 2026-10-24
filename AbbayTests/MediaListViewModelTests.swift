//
//  MediaListViewModelTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class MediaListViewModelTests: XCTestCase {
    private var testSuite: UserDefaults?
    private var suiteName: String?
    private var mockFileLoader: MockFileLoader?
    private var mockLoadAll: MockLoadAllAudiosUseCase?
    private var sharedWriterOriginal: LibrarySnapshotWriterProtocol?
    private var sharedPublisherOriginal: SiriLibraryPublisherProtocol?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let name = "test.viewmodel-snapshot.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        suite.removePersistentDomain(forName: name)
        suiteName = name
        testSuite = suite
        LibrarySnapshotWriter.defaults = suite
        let loader = MockFileLoader()
        let loadAll = MockLoadAllAudiosUseCase()
        mockFileLoader = loader
        mockLoadAll = loadAll

        sharedWriterOriginal = LibrarySnapshotWriter.shared
        LibrarySnapshotWriter.shared = LibrarySnapshotWriter(loadAllAudios: loadAll)
        sharedPublisherOriginal = SiriLibraryPublisher.shared
    }

    override func tearDownWithError() throws {
        if let name = suiteName, let suite = testSuite {
            suite.removePersistentDomain(forName: name)
        }
        LibrarySnapshotWriter.defaults = AppGroup.defaults
        if let original = sharedWriterOriginal {
            LibrarySnapshotWriter.shared = original
        }
        if let original = sharedPublisherOriginal {
            SiriLibraryPublisher.shared = original
        }
        try super.tearDownWithError()
    }

    @MainActor
    func test_importAudio_appendsNonDuplicates_writesSnapshot() async throws {
        var modelA = AudioModel(url: URL(string: "file:///a.m4a"))
        modelA.title = "A"
        let loader = try XCTUnwrap(mockFileLoader)
        let loadAll = try XCTUnwrap(mockLoadAll)
        loader.modelsToReturn = [modelA]

        let viewModel = MediaListViewModel(
            playback: PlaybackCenter(player: MockPlayer()),
            loadAllAudiosUseCase: loadAll,
            deleteAudioUseCase: MockDeleteAudioUseCase(),
            fileLoader: loader
        )

        let url = try XCTUnwrap(URL(string: "file:///a.m4a"))
        await viewModel.importAudio(from: [url])

        XCTAssertEqual(viewModel.audioList.count, 1)
        XCTAssertEqual(viewModel.audioList.first?.title, "A")

        let suite = try XCTUnwrap(testSuite)
        let data = try XCTUnwrap(suite.data(forKey: LibrarySnapshotWriter.key))
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        XCTAssertEqual(snapshot.audios.first?.title, "A")
    }

    @MainActor
    func test_addLibriVoxBook_appendsOnceAndWritesSnapshot() throws {
        let loadAll = try XCTUnwrap(mockLoadAll)
        let viewModel = MediaListViewModel(
            playback: PlaybackCenter(player: MockPlayer()),
            loadAllAudiosUseCase: loadAll,
            deleteAudioUseCase: MockDeleteAudioUseCase(),
            fileLoader: try XCTUnwrap(mockFileLoader)
        )
        var book = AudioModel(url: URL(string: "librivox://book/7"))
        book.title = "Remote"
        book.librivoxID = "7"

        viewModel.addLibriVoxBook(book)
        viewModel.addLibriVoxBook(book)

        XCTAssertEqual(viewModel.audioList.map(\.librivoxID), ["7"])
        let suite = try XCTUnwrap(testSuite)
        let data = try XCTUnwrap(suite.data(forKey: LibrarySnapshotWriter.key))
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        XCTAssertEqual(snapshot.audios.first?.title, "Remote")
    }

    /// The snapshot write is the one path to Siri: it publishes, and publishing refreshes the App
    /// Shortcut parameters. Import and LibriVox-add reach it once each, with no direct refresh of
    /// their own (#84).
    @MainActor
    func test_importAndAddLibriVoxBook_publishToSiriOnceEach() async throws {
        let spy = PublishCountingSpy()
        let loader = try XCTUnwrap(mockFileLoader)
        let viewModel = MediaListViewModel(
            playback: PlaybackCenter(player: MockPlayer()),
            loadAllAudiosUseCase: try XCTUnwrap(mockLoadAll),
            deleteAudioUseCase: MockDeleteAudioUseCase(),
            fileLoader: loader
        )
        SiriLibraryPublisher.shared = spy
        var imported = AudioModel(url: URL(string: "file:///a.m4a"))
        imported.title = "A"
        loader.modelsToReturn = [imported]
        var remote = AudioModel(url: URL(string: "librivox://book/7"))
        remote.title = "Remote"

        await viewModel.importAudio(from: [try XCTUnwrap(imported.url)])
        viewModel.addLibriVoxBook(remote)

        XCTAssertEqual(spy.publishedTitles, [["A"], ["A", "Remote"]])
    }

    @MainActor
    func test_deleteAudio_writesSnapshot() async throws {
        var modelA = AudioModel(url: URL(string: "file:///a.m4a"))
        modelA.title = "A"
        let loader = try XCTUnwrap(mockFileLoader)
        let loadAll = try XCTUnwrap(mockLoadAll)
        loadAll.stub = [modelA]

        let viewModel = MediaListViewModel(
            playback: PlaybackCenter(player: MockPlayer()),
            loadAllAudiosUseCase: loadAll,
            deleteAudioUseCase: MockDeleteAudioUseCase(),
            fileLoader: loader
        )
        // init's defer block populates audioList from loadAllAudios
        XCTAssertEqual(viewModel.audioList.count, 1)

        viewModel.deleteAudio(modelA)

        XCTAssertEqual(viewModel.audioList.count, 0)
        let suite = try XCTUnwrap(testSuite)
        let data = try XCTUnwrap(suite.data(forKey: LibrarySnapshotWriter.key))
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        XCTAssertEqual(snapshot.audios.count, 0)
    }

    // MARK: - Refresh from storage on a book switch (task 4 review I1, I2)

    private let urlA = URL(string: "file:///a.m4a")
    private let urlB = URL(string: "file:///b.m4a")

    private func book(_ title: String, url: URL?, currentTime: Double = 0, bookmark: Data? = nil) -> AudioModel {
        AudioModel(
            title: title,
            artist: "Author",
            duration: 1000,
            currentTime: currentTime,
            url: url,
            bookmarkData: bookmark
        )
    }

    @MainActor
    private func makeViewModel(
        player: MockPlayer = MockPlayer(),
        loadAudio: MockLoadAudioUseCase,
        presentation: PlayerPresentation? = nil
    ) throws -> (MediaListViewModel, PlaybackCenter) {
        let center = PlaybackCenter(player: player, loadAudio: loadAudio)
        let viewModel = MediaListViewModel(
            playback: center,
            presentation: presentation,
            loadAllAudiosUseCase: try XCTUnwrap(mockLoadAll),
            deleteAudioUseCase: MockDeleteAudioUseCase(),
            fileLoader: try XCTUnwrap(mockFileLoader),
            loadAudioUseCase: loadAudio
        )
        return (viewModel, center)
    }

    /// What the root does when `PlaybackState.loadedBook` changes: hand the new book to the model.
    @MainActor
    private func announce(_ book: AudioModel, player: MockPlayer, center: PlaybackCenter, to viewModel: MediaListViewModel) {
        player.emitPlayUrl(book)
        viewModel.loadedBookChanged(to: center.state.loadedBook)
    }

    /// I1: the outgoing book's row must show where it stopped, not the position loaded with the
    /// list, and replaying it must resume there.
    @MainActor
    func test_bookSwitch_refreshesTheOutgoingBookFromStorage() throws {
        try XCTUnwrap(mockLoadAll).stub = [book("A", url: urlA), book("B", url: urlB)]
        let player = MockPlayer()
        let loadAudio = MockLoadAudioUseCase()
        let (viewModel, center) = try makeViewModel(player: player, loadAudio: loadAudio)
        announce(book("A", url: urlA), player: player, center: center, to: viewModel)
        // The player saved A at 600 s before announcing B.
        loadAudio.stubs[try XCTUnwrap(urlA).absoluteString] = book("A", url: urlA, currentTime: 600)

        announce(book("B", url: urlB), player: player, center: center, to: viewModel)

        let rowA = try XCTUnwrap(viewModel.audioList.first { $0.url == urlA })
        XCTAssertEqual(rowA.currentTime, 600)
        let playback = PlaybackState()
        playback.setLoadedBook(book("B", url: urlB))
        let detail = MediaView.DetailModel(book: rowA, state: playback, entry: nil)
        XCTAssertTrue(detail.detailLine.contains("6m 40s"), "1000 s - 600 s left: \(detail.detailLine)")

        let rowPlayer = MockPlayer()
        MediaViewModel(rowA, player: rowPlayer, downloads: nil).play()
        XCTAssertEqual(rowPlayer.playCalls.last?.currentTime, 600)
    }

    /// I2: once the player has made the bookmark, later presses must pass it (and the stored
    /// position), so the player never writes the list's old position again.
    @MainActor
    func test_playEvent_refreshesTheIncomingBookFromStorage() throws {
        try XCTUnwrap(mockLoadAll).stub = [book("A", url: urlA)]
        let player = MockPlayer()
        let loadAudio = MockLoadAudioUseCase()
        let (viewModel, center) = try makeViewModel(player: player, loadAudio: loadAudio)
        let stored = book("A", url: urlA, currentTime: 600, bookmark: Data([7]))
        loadAudio.stubs[try XCTUnwrap(urlA).absoluteString] = stored

        announce(book("A", url: urlA, bookmark: Data([7])), player: player, center: center, to: viewModel)

        let rowA = try XCTUnwrap(viewModel.audioList.first)
        let rowPlayer = MockPlayer()
        MediaViewModel(rowA, player: rowPlayer, downloads: nil).play()
        XCTAssertEqual(rowPlayer.playCalls.last?.bookmarkData, Data([7]))
        XCTAssertEqual(rowPlayer.playCalls.last?.currentTime, 600)
    }

    @MainActor
    func test_bookSwitch_withNothingStored_keepsTheListModel() throws {
        try XCTUnwrap(mockLoadAll).stub = [book("A", url: urlA, currentTime: 42)]
        let player = MockPlayer()
        let (viewModel, center) = try makeViewModel(player: player, loadAudio: MockLoadAudioUseCase())

        announce(book("A", url: urlA), player: player, center: center, to: viewModel)
        announce(book("B", url: urlB), player: player, center: center, to: viewModel)

        XCTAssertEqual(viewModel.audioList.map(\.currentTime), [42])
    }

    /// A book already loaded when the list is built is the "outgoing" book of the first switch.
    @MainActor
    func test_firstSwitch_afterLaunchWithABookLoaded_refreshesThatBook() throws {
        try XCTUnwrap(mockLoadAll).stub = [book("A", url: urlA), book("B", url: urlB)]
        let player = MockPlayer()
        player.url = urlA
        let loadAudio = MockLoadAudioUseCase()
        loadAudio.stubs[try XCTUnwrap(urlA).absoluteString] = book("A", url: urlA)
        let (viewModel, center) = try makeViewModel(player: player, loadAudio: loadAudio)
        loadAudio.stubs[try XCTUnwrap(urlA).absoluteString] = book("A", url: urlA, currentTime: 300)

        announce(book("B", url: urlB), player: player, center: center, to: viewModel)

        XCTAssertEqual(viewModel.audioList.first { $0.url == urlA }?.currentTime, 300)
    }

    // MARK: - Loaded book and delete

    @MainActor
    func test_deletingTheLoadedBook_hidesTheBarAndClosesDetails() throws {
        let loaded = book("A", url: urlA)
        try XCTUnwrap(mockLoadAll).stub = [loaded, book("B", url: urlB)]
        let player = MockPlayer()
        player.url = urlA
        let loadAudio = MockLoadAudioUseCase()
        loadAudio.stubs[try XCTUnwrap(urlA).absoluteString] = loaded
        let presentation = PlayerPresentation()
        let (viewModel, center) = try makeViewModel(player: player, loadAudio: loadAudio, presentation: presentation)
        presentation.open(loaded, animated: false)
        XCTAssertEqual(center.state.loadedBook?.url, urlA)

        viewModel.deleteAudio(loaded)

        XCTAssertEqual(player.unloadCallCount, 1)
        XCTAssertNil(presentation.presentedBook)
        XCTAssertNil(center.state.loadedBook)
        XCTAssertEqual(viewModel.audioList.map(\.url), [urlB])
    }

    @MainActor
    func test_deletingAnotherBook_keepsPlaybackAndDetails() throws {
        let loaded = book("A", url: urlA)
        let other = book("B", url: urlB)
        try XCTUnwrap(mockLoadAll).stub = [loaded, other]
        let player = MockPlayer()
        player.url = urlA
        let loadAudio = MockLoadAudioUseCase()
        loadAudio.stubs[try XCTUnwrap(urlA).absoluteString] = loaded
        let presentation = PlayerPresentation()
        let (viewModel, center) = try makeViewModel(player: player, loadAudio: loadAudio, presentation: presentation)
        presentation.open(loaded, animated: false)

        viewModel.deleteAudio(other)

        XCTAssertEqual(player.unloadCallCount, 0)
        XCTAssertEqual(presentation.presentedBook?.url, urlA)
        XCTAssertEqual(center.state.loadedBook?.url, urlA)
    }

    /// Details open on a book that isn't loaded (a row tap doesn't start playback): deleting it
    /// closes the details but leaves the loaded book alone.
    @MainActor
    func test_deletingThePresentedBook_closesDetailsOnly() throws {
        let loaded = book("A", url: urlA)
        let presented = book("B", url: urlB)
        try XCTUnwrap(mockLoadAll).stub = [loaded, presented]
        let player = MockPlayer()
        player.url = urlA
        let loadAudio = MockLoadAudioUseCase()
        loadAudio.stubs[try XCTUnwrap(urlA).absoluteString] = loaded
        let presentation = PlayerPresentation()
        let (viewModel, center) = try makeViewModel(player: player, loadAudio: loadAudio, presentation: presentation)
        presentation.open(presented, animated: false)

        viewModel.deleteAudio(presented)

        XCTAssertNil(presentation.presentedBook)
        XCTAssertEqual(player.unloadCallCount, 0)
        XCTAssertEqual(center.state.loadedBook?.url, urlA)
    }
}

private final class PublishCountingSpy: SiriLibraryPublisherProtocol {
    private(set) var publishedTitles: [[String]] = []

    func publish(audios: [AudioModel]) {
        publishedTitles.append(audios.map(\.title))
    }
}
