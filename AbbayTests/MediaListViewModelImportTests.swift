//
//  MediaListViewModelImportTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// #115: an import that drops files says which ones, instead of leaving the user to guess.
final class MediaListViewModelImportTests: XCTestCase {
    private var mockFileLoader: MockFileLoader?
    private var sharedWriterOriginal: LibrarySnapshotWriterProtocol?

    override func setUpWithError() throws {
        try super.setUpWithError()
        sharedWriterOriginal = LibrarySnapshotWriter.shared
        LibrarySnapshotWriter.shared = MockLibrarySnapshotWriter()
        mockFileLoader = MockFileLoader()
    }

    override func tearDownWithError() throws {
        if let original = sharedWriterOriginal {
            LibrarySnapshotWriter.shared = original
        }
        try super.tearDownWithError()
    }

    @MainActor
    private func makeImportingViewModel(
        notices: MockNoticeReporter,
        debugImportURLs: [URL]? = nil
    ) throws -> MediaListViewModel {
        MediaListViewModel(
            playback: PlaybackCenter(player: MockPlayer()),
            loadAllAudiosUseCase: MockLoadAllAudiosUseCase(),
            deleteAudioUseCase: MockDeleteAudioUseCase(),
            fileLoader: try XCTUnwrap(mockFileLoader),
            noticeReporter: notices,
            debugImportURLs: debugImportURLs
        )
    }

    /// Select three, one fails: the two rows appear and the user is told which one didn't.
    @MainActor
    func test_importAudio_withAFailedFile_addsTheRestAndReportsTheFailedName() async throws {
        let loader = try XCTUnwrap(mockFileLoader)
        let good = [AudioModel(title: "A", url: URL(string: "file:///a.m4a")),
                    AudioModel(title: "B", url: URL(string: "file:///b.m4a"))]
        let broken = URL(fileURLWithPath: "/picked/Broken Book.mp3")
        loader.modelsToReturn = good
        loader.failedURLsToReturn = [broken]
        let notices = MockNoticeReporter()
        let viewModel = try makeImportingViewModel(notices: notices)

        await viewModel.importAudio(from: good.compactMap(\.url) + [broken])

        XCTAssertEqual(viewModel.audioList.map(\.title), ["A", "B"])
        XCTAssertEqual(notices.notices, [.importFailed(fileNames: ["Broken Book.mp3"])])
    }

    @MainActor
    func test_importAudio_withEveryFileFailing_reportsHowManyAndWhich() async throws {
        let loader = try XCTUnwrap(mockFileLoader)
        let failed = [URL(fileURLWithPath: "/picked/One.mp3"), URL(fileURLWithPath: "/picked/Two.m4b")]
        loader.failedURLsToReturn = failed
        let notices = MockNoticeReporter()
        let viewModel = try makeImportingViewModel(notices: notices)

        await viewModel.importAudio(from: failed)

        XCTAssertTrue(viewModel.audioList.isEmpty)
        XCTAssertEqual(notices.notices, [.importFailed(fileNames: ["One.mp3", "Two.m4b"])])
    }

    @MainActor
    func test_importAudio_whenEverythingLoads_reportsNothing() async throws {
        let loader = try XCTUnwrap(mockFileLoader)
        loader.modelsToReturn = [AudioModel(title: "A", url: URL(string: "file:///a.m4a"))]
        let notices = MockNoticeReporter()
        let viewModel = try makeImportingViewModel(notices: notices)

        await viewModel.importAudio(from: [try XCTUnwrap(URL(string: "file:///a.m4a"))])

        XCTAssertEqual(notices.notices, [])
    }

    @MainActor
    func test_startImport_presentsThePicker() throws {
        let viewModel = try makeImportingViewModel(notices: MockNoticeReporter())

        viewModel.startImport()

        XCTAssertTrue(viewModel.isShowingFilePicker)
    }

    /// `-stubFailingImport`: UI tests can't drive the system picker, so the debug URLs are imported
    /// straight away instead.
    @MainActor
    func test_startImport_withDebugURLs_importsThemInsteadOfPresentingThePicker() async throws {
        let loader = try XCTUnwrap(mockFileLoader)
        let missing = URL(fileURLWithPath: "/tmp/missing/Missing Book.mp3")
        loader.failedURLsToReturn = [missing]
        let notices = MockNoticeReporter()
        let reported = expectation(description: "import reported")
        notices.onReport = { _ in reported.fulfill() }
        let viewModel = try makeImportingViewModel(notices: notices, debugImportURLs: [missing])

        viewModel.startImport()

        await fulfillment(of: [reported], timeout: 2)
        XCTAssertFalse(viewModel.isShowingFilePicker)
        XCTAssertEqual(loader.loadedURLs, [[missing]])
    }
}
