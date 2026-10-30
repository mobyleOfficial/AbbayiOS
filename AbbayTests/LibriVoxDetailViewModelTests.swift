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

    private var book: LibriVoxBook { listing(language: "English") }

    private func listing(language: String) -> LibriVoxBook {
        LibriVoxBook(
            id: "moby_dick_librivox",
            title: "Moby Dick",
            authors: "Herman Melville",
            descriptionText: "A whale.",
            language: language,
            totalSeconds: 120,
            coverURL: URL(fileURLWithPath: "/cover"),
            sections: [
                .init(title: "One", seconds: 60, listenURL: URL(fileURLWithPath: "/1.mp3")),
                .init(title: "Two", seconds: 60, listenURL: URL(fileURLWithPath: "/2.mp3"))
            ]
        )
    }

    private func makeSUT(
        totalBytes: Int64,
        cellular: Bool,
        preference: CellularDownloadPreference = .ask,
        language: String = "English",
        recordLanguage: @escaping (String, URL?) -> Void = { _, _ in }
    ) async -> LibriVoxDetailViewModel {
        client.detailsResult = .success(
            LibriVoxBookDetails(book: listing(language: language), sectionBytes: [totalBytes, 0])
        )
        path.isMetered = cellular
        let sut = LibriVoxDetailViewModel(
            book: book,
            client: client,
            downloads: downloads,
            downloadStates: store,
            saveAudio: save,
            path: path,
            loadAudio: MockLoadAudioUseCase(),
            cellularPreference: { preference },
            recordLanguage: recordLanguage,
            noticeReporter: notices,
            onAdded: { [unowned self] in added.append($0) },
            openPlayer: { [unowned self] in opened.append($0) }
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
            book: book,
            client: client,
            downloads: downloads,
            downloadStates: store,
            saveAudio: save,
            path: path,
            loadAudio: MockLoadAudioUseCase(),
            onAdded: { _ in },
            openPlayer: { _ in }
        )

        await sut.load()

        XCTAssertNil(sut.details)
        XCTAssertTrue(sut.loadFailed)
    }

    func test_download_recordsTheListedLanguageAsAHint() async {
        let settings = AppSettings(store: InMemoryKeyValueStore())
        let sut = await makeSUT(
            totalBytes: 10_000_000,
            cellular: false,
            language: "eng",
            recordLanguage: { settings.setReadAlongLanguage($0, for: $1) }
        )

        sut.downloadTapped()
        await waitUntil { !downloads.enqueued.isEmpty }

        XCTAssertNotNil(sut.addedBook)
        XCTAssertEqual(settings.readAlongLanguage(for: sut.addedBook?.url), "en")
    }

    func test_download_recordsNothingForALanguageItDoesNotKnow() async {
        var recorded: [String] = []
        let sut = await makeSUT(
            totalBytes: 10_000_000,
            cellular: false,
            language: "Klingon",
            recordLanguage: { code, _ in recorded.append(code) }
        )

        sut.downloadTapped()
        await waitUntil { !downloads.enqueued.isEmpty }

        XCTAssertTrue(recorded.isEmpty)
    }

    func test_download_smallBook_startsWithCellularAllowed() async {
        let sut = await makeSUT(totalBytes: 10_000_000, cellular: true)

        sut.downloadTapped()
        await waitUntil { !downloads.enqueued.isEmpty }

        XCTAssertFalse(sut.isShowingCellularAlert)
        XCTAssertEqual(downloads.enqueued.map(\.allowsCellularDownload), [true])
    }

    /// Download must not just do nothing when the book can't be saved (#115).
    func test_download_whenTheBookCannotBeSaved_reportsItAndStartsNothing() async {
        let sut = await makeSUT(totalBytes: 10_000_000, cellular: false)
        save.error = NSError(domain: "test", code: 1)

        sut.downloadTapped()
        await waitUntil { !notices.notices.isEmpty }

        XCTAssertEqual(notices.notices, [.saveFailed])
        XCTAssertNil(sut.addedBook)
        XCTAssertTrue(downloads.enqueued.isEmpty)
        XCTAssertTrue(added.isEmpty)
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

    // MARK: - The Settings preference

    func test_download_largeOnCellular_withAlways_startsOnCellularWithoutAsking() async {
        let sut = await makeSUT(totalBytes: 200_000_000, cellular: true, preference: .always)

        sut.downloadTapped()
        await waitUntil { !downloads.enqueued.isEmpty }

        XCTAssertFalse(sut.isShowingCellularAlert)
        XCTAssertEqual(downloads.enqueued.map(\.allowsCellularDownload), [true])
    }

    func test_download_largeOnCellular_withWifiOnly_waitsForWiFiWithoutAsking() async {
        let sut = await makeSUT(totalBytes: 200_000_000, cellular: true, preference: .wifiOnly)

        sut.downloadTapped()
        await waitUntil { !downloads.enqueued.isEmpty }

        XCTAssertFalse(sut.isShowingCellularAlert)
        XCTAssertEqual(downloads.enqueued.map(\.allowsCellularDownload), [false])
    }

    func test_download_largeOnWiFi_startsWithCellularDisallowed() async {
        let sut = await makeSUT(totalBytes: 200_000_000, cellular: false)

        sut.downloadTapped()
        await waitUntil { !downloads.enqueued.isEmpty }

        XCTAssertFalse(sut.isShowingCellularAlert)
        XCTAssertEqual(downloads.enqueued.map(\.allowsCellularDownload), [false])
    }

    /// "Wait for Wi-Fi" at home with Low Data Mode on: the page says why nothing moves (#148).
    func test_downloadHold_onlyForTheAddedWiFiOnlyBookWhileLowDataModeIsOn() async {
        let sut = await makeSUT(totalBytes: 200_000_000, cellular: false)
        path.isLowDataMode = true
        XCTAssertNil(sut.downloadHold, "Not added yet")

        sut.downloadTapped()
        await waitUntil { !downloads.enqueued.isEmpty }
        let waiting = BookDownloadState(chapters: [.waiting, .waiting], expectedBytes: [1, 1], isPaused: false)
        downloads.statesSubject.send([book.id: waiting])

        XCTAssertEqual(sut.downloadHold, .lowDataMode)
        path.isLowDataMode = false
        XCTAssertNil(sut.downloadHold)
    }

    /// "Wait for Wi-Fi" chosen on cellular: the page says it waits for Wi-Fi, then a hotspot (#171).
    func test_downloadHold_onCellularOrAHotspot_saysWhich() async {
        let sut = await makeSUT(totalBytes: 200_000_000, cellular: false)
        path.isMetered = true
        path.hold = .cellular

        sut.downloadTapped()
        XCTAssertTrue(sut.isShowingCellularAlert)
        sut.confirmCellular(continue: false)
        await waitUntil { !downloads.enqueued.isEmpty }
        let waiting = BookDownloadState(chapters: [.waiting, .waiting], expectedBytes: [1, 1], isPaused: false)
        downloads.statesSubject.send([book.id: waiting])

        XCTAssertEqual(sut.downloadHold, .cellular)
        path.hold = .personalHotspot
        XCTAssertEqual(sut.downloadHold, .personalHotspot)
    }

    func test_downloadHold_nilForABookAllowedOnCellular() async {
        let sut = await makeSUT(totalBytes: 1000, cellular: false)
        path.isLowDataMode = true

        sut.downloadTapped()
        await waitUntil { !downloads.enqueued.isEmpty }
        let waiting = BookDownloadState(chapters: [.waiting, .waiting], expectedBytes: [1, 1], isPaused: false)
        downloads.statesSubject.send([book.id: waiting])

        XCTAssertNil(sut.downloadHold)
    }

    func test_retryChapter_forwardsToTheDownloadManager() async {
        let sut = await makeSUT(totalBytes: 1000, cellular: false)

        sut.retryChapter(1)

        XCTAssertEqual(downloads.retried.map(\.chapterIndex), [1])
        XCTAssertEqual(downloads.retried.map(\.bookID), ["moby_dick_librivox"])
    }

    func test_download_savesBookAndCallsOnAdded() async {
        client.coverResult = Data([1, 2, 3])
        let sut = await makeSUT(totalBytes: 1000, cellular: false)

        sut.downloadTapped()
        await waitUntil { !added.isEmpty }

        XCTAssertEqual(save.savedModels.map(\.url), [URL(string: "librivox://book/moby_dick_librivox")])
        XCTAssertEqual(save.savedModels.first?.imageData, Data([1, 2, 3]))
        XCTAssertEqual(added.map(\.librivoxID), ["moby_dick_librivox"])
        XCTAssertEqual(sut.addedBook?.librivoxID, "moby_dick_librivox")
    }

    func test_existingBook_startsAddedAndDownloadDoesNothing() async {
        var existing = AudioModel(url: LibriVoxIdentity.bookURL(id: "moby_dick_librivox"))
        existing.librivoxID = "moby_dick_librivox"
        let loadAudio = MockLoadAudioUseCase()
        loadAudio.stubs["librivox://book/moby_dick_librivox"] = existing
        client.detailsResult = .success(LibriVoxBookDetails(book: book, sectionBytes: [1000, 0]))
        let sut = LibriVoxDetailViewModel(
            book: book,
            client: client,
            downloads: downloads,
            downloadStates: store,
            saveAudio: save,
            path: path,
            loadAudio: loadAudio,
            onAdded: { [unowned self] in added.append($0) },
            openPlayer: { _ in }
        )
        await sut.load()

        XCTAssertEqual(sut.addedBook?.librivoxID, "moby_dick_librivox")
        sut.downloadTapped()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(save.savedModels.isEmpty)
        XCTAssertTrue(downloads.enqueued.isEmpty)
        XCTAssertTrue(added.isEmpty)
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

        downloads.statesSubject.send(["other": state, "moby_dick_librivox": state])
        await waitUntil { sut.downloadState != nil }

        XCTAssertEqual(sut.downloadState, state)
    }

    /// Like `PlayerViewModel`: once every chapter is downloaded there is no per-chapter status and
    /// no progress bar, so the page and the player sheet show the same list.
    func test_statesPublisher_completeDownload_clearsDownloadState() async {
        let sut = await makeSUT(totalBytes: 1000, cellular: false)
        let partial = BookDownloadState(chapters: [.downloaded, .waiting], expectedBytes: [1, 1], isPaused: false)
        let complete = BookDownloadState(chapters: [.downloaded, .downloaded], expectedBytes: [1, 1], isPaused: false)
        downloads.statesSubject.send(["moby_dick_librivox": partial])
        await waitUntil { sut.downloadState != nil }

        downloads.statesSubject.send(["moby_dick_librivox": complete])
        await waitUntil { sut.downloadState == nil }

        XCTAssertNil(sut.downloadState)
    }

    func test_play_beforeDownloadFinishes_callsPlayer() async {
        let sut = await makeSUT(totalBytes: 1000, cellular: false)
        sut.downloadTapped()
        await waitUntil { sut.addedBook != nil }

        sut.play()

        XCTAssertEqual(player.playCalls.map(\.librivoxID), ["moby_dick_librivox"])
    }

    /// Play hands the book to the one player presentation, the same one a Library row opens.
    func test_play_opensThePlayerOnTheAddedBook() async {
        let sut = await makeSUT(totalBytes: 1000, cellular: false)
        sut.downloadTapped()
        await waitUntil { sut.addedBook != nil }
        XCTAssertTrue(opened.isEmpty)

        sut.play()

        XCTAssertEqual(opened.map(\.librivoxID), ["moby_dick_librivox"])
    }

    func test_play_beforeTheBookIsAdded_doesNotOpenThePlayer() async {
        let sut = await makeSUT(totalBytes: 1000, cellular: false)

        sut.play()

        XCTAssertTrue(opened.isEmpty)
        XCTAssertTrue(player.playCalls.isEmpty)
    }
}
