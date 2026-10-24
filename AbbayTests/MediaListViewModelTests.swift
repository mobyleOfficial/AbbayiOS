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
    }

    override func tearDownWithError() throws {
        if let name = suiteName, let suite = testSuite {
            suite.removePersistentDomain(forName: name)
        }
        LibrarySnapshotWriter.defaults = AppGroup.defaults
        if let original = sharedWriterOriginal {
            LibrarySnapshotWriter.shared = original
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
            playerObserver: MockPlayerObserver(),
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
            playerObserver: MockPlayerObserver(),
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

    @MainActor
    func test_deleteAudio_writesSnapshot() async throws {
        var modelA = AudioModel(url: URL(string: "file:///a.m4a"))
        modelA.title = "A"
        let loader = try XCTUnwrap(mockFileLoader)
        let loadAll = try XCTUnwrap(mockLoadAll)
        loadAll.stub = [modelA]

        let viewModel = MediaListViewModel(
            playerObserver: MockPlayerObserver(),
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

    private func makeViewModel(
        observer: MockPlayerObserver,
        loadAudio: MockLoadAudioUseCase
    ) throws -> MediaListViewModel {
        MediaListViewModel(
            playerObserver: observer,
            loadAllAudiosUseCase: try XCTUnwrap(mockLoadAll),
            deleteAudioUseCase: MockDeleteAudioUseCase(),
            fileLoader: try XCTUnwrap(mockFileLoader),
            loadAudioUseCase: loadAudio
        )
    }

    /// I1: the outgoing book's row must show where it stopped, not the position loaded with the
    /// list, and replaying it must resume there.
    @MainActor
    func test_bookSwitch_refreshesTheOutgoingBookFromStorage() throws {
        try XCTUnwrap(mockLoadAll).stub = [book("A", url: urlA), book("B", url: urlB)]
        let observer = MockPlayerObserver()
        let loadAudio = MockLoadAudioUseCase()
        let viewModel = try makeViewModel(observer: observer, loadAudio: loadAudio)
        observer.emitPlayUrl(book("A", url: urlA))
        // The player saved A at 600 s before announcing B.
        loadAudio.stubs[try XCTUnwrap(urlA).absoluteString] = book("A", url: urlA, currentTime: 600)

        observer.emitPlayUrl(book("B", url: urlB))

        let rowA = try XCTUnwrap(viewModel.audioList.first { $0.url == urlA })
        XCTAssertEqual(rowA.currentTime, 600)
        let playback = PlaybackState()
        playback.setLoadedBook(book("B", url: urlB))
        let detail = MediaView.DetailModel(book: rowA, state: playback, entry: nil)
        XCTAssertTrue(detail.detailLine.contains("6m 40s"), "1000 s - 600 s left: \(detail.detailLine)")

        let player = MockPlayer()
        MediaViewModel(rowA, player: player, downloads: nil).play()
        XCTAssertEqual(player.playCalls.last?.currentTime, 600)
    }

    /// I2: once the player has made the bookmark, later presses must pass it (and the stored
    /// position), so the player never writes the list's old position again.
    @MainActor
    func test_playEvent_refreshesTheIncomingBookFromStorage() throws {
        try XCTUnwrap(mockLoadAll).stub = [book("A", url: urlA)]
        let observer = MockPlayerObserver()
        let loadAudio = MockLoadAudioUseCase()
        let viewModel = try makeViewModel(observer: observer, loadAudio: loadAudio)
        let stored = book("A", url: urlA, currentTime: 600, bookmark: Data([7]))
        loadAudio.stubs[try XCTUnwrap(urlA).absoluteString] = stored

        observer.emitPlayUrl(book("A", url: urlA, bookmark: Data([7])))

        let rowA = try XCTUnwrap(viewModel.audioList.first)
        let player = MockPlayer()
        MediaViewModel(rowA, player: player, downloads: nil).play()
        XCTAssertEqual(player.playCalls.last?.bookmarkData, Data([7]))
        XCTAssertEqual(player.playCalls.last?.currentTime, 600)
    }

    @MainActor
    func test_bookSwitch_withNothingStored_keepsTheListModel() throws {
        try XCTUnwrap(mockLoadAll).stub = [book("A", url: urlA, currentTime: 42)]
        let observer = MockPlayerObserver()
        let viewModel = try makeViewModel(observer: observer, loadAudio: MockLoadAudioUseCase())

        observer.emitPlayUrl(book("A", url: urlA))
        observer.emitPlayUrl(book("B", url: urlB))

        XCTAssertEqual(viewModel.audioList.map(\.currentTime), [42])
    }
}
