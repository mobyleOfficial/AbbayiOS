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
}
