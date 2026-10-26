//
//  LibriVoxDetailViewModelLoadingTests.swift
//  AbbayTests
//

@testable import Abbay
import Combine
import XCTest

@MainActor
/// The page while LibriVox is still answering (#258): archive.org's version at once, and a
/// Download tapped meanwhile waits for LibriVox's chapter titles.
final class LibriVoxDetailViewModelLoadingTests: XCTestCase {
    private let client = MockLibriVoxClient()
    private let downloads = MockBookDownloadManager()
    private lazy var store = DownloadStateStore(downloads: downloads, path: path)
    private let save = MockSaveAudioUseCase()
    private let notices = MockNoticeReporter()
    private let path = FakeNetworkPath()
    private let player = MockPlayer()
    private var added: [AudioModel] = []
    private var opened: [AudioModel] = []

    override func setUp() {
        super.setUp()
        DependencyContainer.configure(with: MockDependencyContainer(
            player: player,
            loadAudio: MockLoadAudioUseCase(),
            loadAllAudios: MockLoadAllAudiosUseCase(),
            downloads: downloads
        ))
    }

    override func tearDown() {
        DependencyContainer.reset()
        super.tearDown()
    }

    private var book: LibriVoxBook {
        LibriVoxBook(
            id: "moby_dick_librivox",
            title: "Moby Dick",
            authors: "Herman Melville",
            descriptionText: "A whale.",
            language: "English",
            totalSeconds: 120,
            coverURL: URL(fileURLWithPath: "/cover"),
            sections: [
                .init(title: "One", seconds: 60, listenURL: URL(fileURLWithPath: "/1.mp3")),
                .init(title: "Two", seconds: 60, listenURL: URL(fileURLWithPath: "/2.mp3"))
            ]
        )
    }

    /// archive.org's version: file-name titles, no description.
    private var archivePreview: LibriVoxBookDetails {
        let sections = book.sections.enumerated().map { index, section in
            LibriVoxBook.Section(title: "moby_\(index + 1)", seconds: section.seconds, listenURL: section.listenURL)
        }
        let preview = LibriVoxBook(
            id: book.id,
            title: book.title,
            authors: book.authors,
            descriptionText: "",
            language: book.language,
            totalSeconds: book.totalSeconds,
            coverURL: book.coverURL,
            sections: sections
        )
        return LibriVoxBookDetails(book: preview, sectionBytes: [10, 10])
    }

    private func makeLoadingSUT() -> LibriVoxDetailViewModel {
        client.detailsResult = .success(LibriVoxBookDetails(book: book, sectionBytes: [10, 10]))
        client.previewDetails = archivePreview
        client.holdsFinal = true
        return LibriVoxDetailViewModel(
            book: book,
            client: client,
            downloads: downloads,
            downloadStates: store,
            saveAudio: save,
            path: path,
            loadAudio: MockLoadAudioUseCase(),
            noticeReporter: notices,
            onAdded: { [unowned self] in added.append($0) },
            openPlayer: { [unowned self] in opened.append($0) }
        )
    }

    func test_load_showsThePreviewAtOnce_andAwaitsLibriVox_untilTheFinalArrives() async {
        let sut = makeLoadingSUT()
        let load = Task { await sut.load() }

        await waitUntil { sut.details != nil }
        XCTAssertEqual(sut.details?.book.sections.first?.title, "moby_1")
        XCTAssertTrue(sut.isAwaitingLibriVox)

        client.holdsFinal = false
        await load.value
        XCTAssertEqual(sut.details?.book.sections.first?.title, "One")
        XCTAssertEqual(sut.details?.book.descriptionText, "A whale.")
        XCTAssertFalse(sut.isAwaitingLibriVox)
    }

    func test_download_whileAwaitingLibriVox_waits_thenSavesLibriVoxTitles() async throws {
        let sut = makeLoadingSUT()
        let load = Task { await sut.load() }
        await waitUntil { sut.isAwaitingLibriVox }

        sut.downloadTapped()
        XCTAssertTrue(sut.isDownloadPending)
        XCTAssertTrue(save.savedModels.isEmpty)

        client.holdsFinal = false
        await load.value
        await waitUntil { !save.savedModels.isEmpty }
        XCTAssertFalse(sut.isDownloadPending)
        let saved = try XCTUnwrap(save.savedModels.first)
        XCTAssertEqual(saved.chapters.first?.title, "One")
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
