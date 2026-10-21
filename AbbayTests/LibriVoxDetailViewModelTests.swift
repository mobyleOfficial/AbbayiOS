//
//  LibriVoxDetailViewModelTests.swift
//  AbbayTests
//

@testable import Abbay
import Combine
import XCTest

@MainActor
final class LibriVoxDetailViewModelTests: XCTestCase {
    private let client = MockLibriVoxClient()
    private let downloads = MockBookDownloadManager()
    private let save = MockSaveAudioUseCase()
    private let path = FakeNetworkPath()
    private let player = MockPlayer()
    private var added: [AudioModel] = []

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
            id: "42",
            title: "Moby Dick",
            authors: "Herman Melville",
            descriptionText: "A whale.",
            language: "English",
            totalSeconds: 120,
            archiveIdentifier: "moby",
            coverURL: URL(fileURLWithPath: "/cover"),
            sections: [
                .init(title: "One", seconds: 60, listenURL: URL(fileURLWithPath: "/1.mp3")),
                .init(title: "Two", seconds: 60, listenURL: URL(fileURLWithPath: "/2.mp3"))
            ]
        )
    }

    private func makeSUT(totalBytes: Int64, cellular: Bool) async -> LibriVoxDetailViewModel {
        client.detailsResult = .success(LibriVoxBookDetails(book: book, sectionBytes: [totalBytes, 0]))
        path.isCellular = cellular
        let sut = LibriVoxDetailViewModel(
            book: book,
            client: client,
            downloads: downloads,
            saveAudio: save,
            path: path,
            onAdded: { [unowned self] in added.append($0) }
        )
        await sut.load()
        return sut
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func test_load_failureLeavesDetailsNilAndFlagsError() async {
        client.detailsResult = .failure(URLError(.notConnectedToInternet))
        let sut = LibriVoxDetailViewModel(
            book: book, client: client, downloads: downloads, saveAudio: save, path: path, onAdded: { _ in }
        )

        await sut.load()

        XCTAssertNil(sut.details)
        XCTAssertTrue(sut.loadFailed)
    }

    func test_download_smallBook_startsWithCellularAllowed() async {
        let sut = await makeSUT(totalBytes: 10_000_000, cellular: true)

        sut.downloadTapped()
        await waitUntil { !downloads.enqueued.isEmpty }

        XCTAssertFalse(sut.isShowingCellularAlert)
        XCTAssertEqual(downloads.enqueued.map(\.allowsCellularDownload), [true])
    }

    func test_download_largeOnCellular_showsAlertAndDoesNotStart() async {
        let sut = await makeSUT(totalBytes: 200_000_000, cellular: true)

        sut.downloadTapped()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(sut.isShowingCellularAlert)
        XCTAssertTrue(downloads.enqueued.isEmpty)
        XCTAssertTrue(save.savedModels.isEmpty)
    }

    func test_confirmCellular_continue_startsWithCellularAllowed() async {
        let sut = await makeSUT(totalBytes: 200_000_000, cellular: true)
        sut.downloadTapped()

        sut.confirmCellular(continue: true)
        await waitUntil { !downloads.enqueued.isEmpty }

        XCTAssertEqual(downloads.enqueued.map(\.allowsCellularDownload), [true])
        XCTAssertEqual(save.savedModels.map(\.allowsCellularDownload), [true])
    }

    func test_confirmCellular_wait_startsWithCellularDisallowed() async {
        let sut = await makeSUT(totalBytes: 200_000_000, cellular: true)
        sut.downloadTapped()

        sut.confirmCellular(continue: false)
        await waitUntil { !downloads.enqueued.isEmpty }

        XCTAssertEqual(downloads.enqueued.map(\.allowsCellularDownload), [false])
    }

    func test_download_largeOnWiFi_startsWithCellularDisallowed() async {
        let sut = await makeSUT(totalBytes: 200_000_000, cellular: false)

        sut.downloadTapped()
        await waitUntil { !downloads.enqueued.isEmpty }

        XCTAssertFalse(sut.isShowingCellularAlert)
        XCTAssertEqual(downloads.enqueued.map(\.allowsCellularDownload), [false])
    }

    func test_download_savesBookAndCallsOnAdded() async {
        client.coverResult = Data([1, 2, 3])
        let sut = await makeSUT(totalBytes: 1000, cellular: false)

        sut.downloadTapped()
        await waitUntil { !added.isEmpty }

        XCTAssertEqual(save.savedModels.map(\.url), [URL(string: "librivox://book/42")])
        XCTAssertEqual(save.savedModels.first?.imageData, Data([1, 2, 3]))
        XCTAssertEqual(added.map(\.librivoxID), ["42"])
        XCTAssertEqual(sut.addedBook?.librivoxID, "42")
    }

    func test_download_twice_addsOnlyOnce() async {
        let sut = await makeSUT(totalBytes: 1000, cellular: false)

        sut.downloadTapped()
        sut.downloadTapped()
        await waitUntil { !added.isEmpty }
        sut.downloadTapped()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(save.savedModels.count, 1)
        XCTAssertEqual(downloads.enqueued.count, 1)
        XCTAssertEqual(added.count, 1)
    }

    func test_statesPublisher_updatesDownloadStateForThisBook() async {
        let sut = await makeSUT(totalBytes: 1000, cellular: false)
        let state = BookDownloadState(chapters: [.downloaded, .waiting], expectedBytes: [1, 1], isPaused: false)

        downloads.statesSubject.send(["other": state, "42": state])
        await waitUntil { sut.downloadState != nil }

        XCTAssertEqual(sut.downloadState, state)
    }

    func test_play_beforeDownloadFinishes_callsPlayer() async {
        let sut = await makeSUT(totalBytes: 1000, cellular: false)
        sut.downloadTapped()
        await waitUntil { sut.addedBook != nil }

        sut.play()

        XCTAssertEqual(player.playCalls.map(\.librivoxID), ["42"])
    }
}
