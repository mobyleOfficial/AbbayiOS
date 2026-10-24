//
//  BookDownloadManagerTests.swift
//  AbbayTests
//

@testable import Abbay
import Combine
import NetworkProvider
import XCTest

/// Events go through `MockDownloadProvider`, and every wait is on an expectation fulfilled by a
/// state emission or a recorded call. Nothing sleeps: the backoff retries are captured and fired by hand.
@MainActor
final class BookDownloadManagerTests: XCTestCase {
    private let provider = MockDownloadProvider()
    private let flags = MockUpdateDownloadFlagsUseCase()
    private let loadAll = MockLoadAllAudiosUseCase()
    private let path = FakeNetworkPath()
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("BookDownloadManagerTests-\(UUID().uuidString)", isDirectory: true)
    private var pendingRetries: [(delay: TimeInterval, run: () -> Void)] = []
    private var cancellables = Set<AnyCancellable>()
    private var latestStates: [String: BookDownloadState] = [:]
    private var observers: [() -> Void] = []

    private lazy var sut: BookDownloadManager = {
        let manager = BookDownloadManager(
            provider: provider,
            root: root,
            updateFlags: flags,
            loadAll: loadAll,
            path: path,
            scheduleRetry: { [weak self] delay, retry in self?.pendingRetries.append((delay, retry)) }
        )
        manager.statesPublisher
            .sink { [weak self] states in
                self?.latestStates = states
                self?.notifyObservers()
            }
            .store(in: &cancellables)
        provider.onCall = { [weak self] in self?.notifyObservers() }
        addTeardownBlock { [root] in try? FileManager.default.removeItem(at: root) }
        return manager
    }()
    private var drainCount = 0

    // MARK: - Enqueue

    func test_enqueue_startsFirstTwoMissingChaptersInOrder() throws {
        let book = makeBook()
        try writeChapterFile(0, of: book)

        sut.enqueue(book)

        XCTAssertEqual(provider.startedIDs, ["1#1", "1#2"])
        XCTAssertEqual(provider.startCalls.first?.url, "https://archive.org/download/x/ch1.mp3")
        XCTAssertEqual(latestStates["1"]?.chapters, [.downloaded, .waiting, .waiting, .waiting])
    }

    func test_enqueue_usesBookCellularFlag() {
        sut.enqueue(makeBook(allowsCellular: false))

        XCTAssertEqual(provider.startCalls.map(\.allowsCellularAccess), [false, false])
    }

    func test_enqueue_pausedBook_startsNothing() {
        sut.enqueue(makeBook(isPaused: true))

        XCTAssertTrue(provider.startCalls.isEmpty)
        XCTAssertEqual(latestStates["1"]?.isPaused, true)
    }

    // MARK: - Events

    func test_progress_marksChapterDownloading() async {
        sut.enqueue(makeBook())

        provider.send(.progress(id: "1#0", receivedBytes: 25, expectedBytes: 100))

        await waitUntil { self.latestStates["1"]?.chapters[0] == .downloading(fraction: 0.25) }
    }

    func test_finished_movesFileAndStartsNext() async throws {
        let book = makeBook()
        try writeChapterFile(0, of: book)
        sut.enqueue(book)
        let temp = try makeTempFile(Data([1, 2, 3]))

        provider.send(.finished(id: "1#1", location: temp))

        await waitUntil { self.provider.startedIDs.contains("1#3") }
        let local = try XCTUnwrap(LibriVoxIdentity.localFileURL(for: book.chapters[1], bookID: "1", root: root))
        XCTAssertEqual(try Data(contentsOf: local), Data([1, 2, 3]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
        XCTAssertEqual(latestStates["1"]?.chapters[1], .downloaded)
        XCTAssertEqual(provider.startedIDs, ["1#1", "1#2", "1#3"])
    }

    func test_finished_lastChapter_completesBook() async throws {
        let book = makeBook(chapterCount: 1)
        sut.enqueue(book)

        provider.send(.finished(id: "1#0", location: try makeTempFile(Data([1]))))

        await waitUntil { self.latestStates["1"]?.isComplete == true }
        XCTAssertEqual(latestStates["1"]?.fraction, 1)
    }

    func test_failed_cancelledRequest_isNotAFailure() async {
        sut.enqueue(makeBook(chapterCount: 1))

        provider.send(.failed(id: "1#0", error: .cancelledRequest))
        await drainEvents()

        XCTAssertEqual(latestStates["1"]?.chapters, [.waiting])
        XCTAssertTrue(pendingRetries.isEmpty)
    }

    // MARK: - Prioritize

    func test_prioritize_movesChapterToFront() async throws {
        sut.enqueue(makeBook())
        XCTAssertEqual(provider.startedIDs, ["1#0", "1#1"])

        sut.prioritize(chapterIndex: 3, ofBookID: "1")
        XCTAssertEqual(provider.startedIDs, ["1#0", "1#1"], "No slot is free yet")

        provider.send(.finished(id: "1#0", location: try makeTempFile(Data([0]))))
        await waitUntil { self.provider.startCalls.count == 3 }
        XCTAssertEqual(provider.startedIDs.last, "1#3")
    }

    func test_prioritize_startsRightAwayWhenSlotIsFree() async throws {
        sut.enqueue(makeBook())
        provider.send(.failed(id: "1#0", error: .connection))
        await waitUntil { self.provider.startedIDs.contains("1#2") }
        provider.send(.failed(id: "1#2", error: .connection))
        await waitUntil { self.provider.startedIDs.contains("1#3") }
        provider.send(.failed(id: "1#3", error: .connection))
        await waitUntil { self.pendingRetries.count == 3 }

        sut.prioritize(chapterIndex: 0, ofBookID: "1")

        XCTAssertEqual(provider.startedIDs.last, "1#0")
    }

    // MARK: - Pause / resume

    func test_pause_pausesRunningAndPersistsFlag() async {
        let book = makeBook()
        sut.enqueue(book)

        sut.pause(bookID: "1")

        await waitUntil { self.provider.pauseCalls.count == 2 }
        XCTAssertEqual(Set(provider.pauseCalls), ["1#0", "1#1"])
        XCTAssertEqual(flags.calls, [.init(url: book.url, isDownloadPaused: true, allowsCellularDownload: nil)])
        XCTAssertEqual(latestStates["1"]?.isPaused, true)

        provider.send(.failed(id: "1#0", error: .cancelledRequest))
        provider.send(.failed(id: "1#1", error: .cancelledRequest))
        await drainEvents()
        XCTAssertEqual(startedIDs(ofBook: "1"), ["1#0", "1#1"])
        XCTAssertTrue(pendingRetries.isEmpty)
    }

    func test_resume_restartsAndClearsFlag() async {
        let book = makeBook()
        sut.enqueue(book)
        sut.pause(bookID: "1")
        await waitUntil { self.provider.pauseCalls.count == 2 }

        sut.resume(bookID: "1")

        await waitUntil { self.provider.resumeCalls.filter { ["1#0", "1#1"].contains($0) }.count == 4 }
        XCTAssertEqual(provider.startedIDs, ["1#0", "1#1"], "Resumed from resume data, not restarted")
        XCTAssertEqual(flags.calls.last, .init(url: book.url, isDownloadPaused: false, allowsCellularDownload: nil))
        XCTAssertEqual(latestStates["1"]?.isPaused, false)
    }

    func test_resume_staleCancelOfPausedTask_doesNotUnseatResumedTask() async throws {
        sut.enqueue(makeBook())
        sut.pause(bookID: "1")
        await waitUntil { self.provider.pauseCalls.count == 2 }
        sut.resume(bookID: "1")
        await waitUntil { self.provider.resumeCalls.count == 4 }

        // URLSession reports the paused tasks' cancellation after `pause` returned.
        provider.send(.failed(id: "1#0", error: .cancelledRequest))
        provider.send(.failed(id: "1#1", error: .cancelledRequest))
        provider.send(.finished(id: "1#1", location: try makeTempFile(Data([1]))))

        await waitUntil { self.provider.startedIDs.contains("1#2") }
        await drainEvents()
        XCTAssertEqual(startedIDs(ofBook: "1"), ["1#0", "1#1", "1#2"])
        XCTAssertEqual(provider.resumeCalls.filter { $0 == "1#0" }.count, 2)
    }

    // MARK: - Remove

    func test_delete_cancelsTasksAndRemovesDirectory() throws {
        let book = makeBook()
        try writeChapterFile(0, of: book)
        sut.enqueue(book)

        sut.remove(bookID: "1")

        XCTAssertEqual(provider.cancelCalls, ["1#0", "1#1", "1#2", "1#3"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("1").path))
        XCTAssertNil(latestStates["1"])
    }

    func test_delete_pausedBook_cancelsAfterThePauseSoResumeDataIsDropped() async {
        sut.enqueue(makeBook())
        sut.pause(bookID: "1")

        sut.remove(bookID: "1")

        XCTAssertNil(latestStates["1"])
        await waitUntil { self.provider.cancelCalls.count == 4 }
        XCTAssertEqual(provider.pauseCalls, ["1#0", "1#1"])
        XCTAssertEqual(provider.cancelCalls, ["1#0", "1#1", "1#2", "1#3"])
        XCTAssertTrue(provider.resumableIDs.isEmpty)
    }

    func test_delete_thenFinishedEvent_isIgnored() async throws {
        sut.enqueue(makeBook())
        sut.remove(bookID: "1")
        let temp = try makeTempFile(Data([1]))

        provider.send(.finished(id: "1#0", location: temp))
        provider.send(.progress(id: "1#1", receivedBytes: 1, expectedBytes: 2))
        await drainEvents()

        XCTAssertNil(latestStates["1"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("1").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
    }

    func test_remove_thenEnqueue_staleCancelDoesNotUnseatNewTask() async throws {
        sut.enqueue(makeBook())
        sut.remove(bookID: "1")
        sut.enqueue(makeBook())

        provider.send(.failed(id: "1#0", error: .cancelledRequest))
        provider.send(.finished(id: "1#1", location: try makeTempFile(Data([1]))))

        await waitUntil { self.provider.startedIDs.contains("1#2") }
        await drainEvents()
        XCTAssertEqual(startedIDs(ofBook: "1"), ["1#0", "1#1", "1#0", "1#1", "1#2"])
    }

    // MARK: - Restore

    func test_restore_doesNotDuplicateRunningTasks() async {
        loadAll.stub = [makeBook()]
        provider.running = ["1#0"]

        sut.restore()

        await waitUntil { self.provider.startedIDs.contains("1#1") }
        XCTAssertEqual(provider.startedIDs, ["1#1"])
        XCTAssertFalse(provider.resumeCalls.contains("1#0"))
    }

    func test_restore_resumesFromResumeDataBeforeStarting() async {
        loadAll.stub = [makeBook()]
        provider.resumableIDs = ["1#0"]

        sut.restore()

        await waitUntil { self.provider.startedIDs.contains("1#1") }
        XCTAssertEqual(provider.resumeCalls.first, "1#0")
        XCTAssertEqual(provider.startedIDs, ["1#1"])
    }

    func test_restore_finishedEventDeliveredAtRelaunch_keepsFileAndDoesNotRedownload() async throws {
        let book = makeBook()
        loadAll.stub = [book]
        provider.holdsRunningIDs = true
        let temp = try makeTempFile(Data([7]))

        sut.restore()
        // The background session hands over downloads that finished while the app was dead as
        // soon as it is created, while `restore()` is still asking for the running tasks.
        provider.send(.finished(id: "1#0", location: temp))

        await waitUntil { self.latestStates["1"]?.chapters.first == .downloaded }
        XCTAssertTrue(provider.startCalls.isEmpty, "Nothing starts before the running tasks are known")
        provider.releaseRunningIDs()
        await waitUntil { self.provider.startedIDs.contains("1#2") }
        let local = try XCTUnwrap(LibriVoxIdentity.localFileURL(for: book.chapters[0], bookID: "1", root: root))
        XCTAssertEqual(try Data(contentsOf: local), Data([7]))
        XCTAssertEqual(provider.startedIDs, ["1#1", "1#2"])
        XCTAssertFalse(provider.resumeCalls.contains("1#0"))
    }

    func test_restore_skipsPausedBooks() async throws {
        let book = makeBook(isPaused: true)
        try writeChapterFile(0, of: book)
        loadAll.stub = [book, importedBook()]

        sut.restore()

        await waitUntil { self.latestStates["1"] != nil }
        XCTAssertEqual(latestStates["1"]?.isPaused, true)
        XCTAssertEqual(latestStates["1"]?.chapters.first, .downloaded)
        XCTAssertEqual(latestStates.count, 1)
        XCTAssertTrue(provider.startCalls.isEmpty)
        XCTAssertTrue(provider.resumeCalls.isEmpty)
    }

    // MARK: - State

    func test_fraction_isBytesWeighted() throws {
        let book = makeBook(chapterBytes: [10, 30])
        try writeChapterFile(0, of: book)

        sut.enqueue(book)

        XCTAssertEqual(latestStates["1"]?.fraction, 0.25)
    }

    func test_fraction_fallsBackToChapterCountWithoutBytes() throws {
        let book = makeBook(chapterBytes: [0, 0, 0, 0])
        try writeChapterFile(0, of: book)

        sut.enqueue(book)

        XCTAssertEqual(latestStates["1"]?.fraction, 0.25)
    }

    func test_statesPublisher_emitsOnMainThread() async {
        sut.enqueue(makeBook())
        let onMain = expectation(description: "emitted on main")
        sut.statesPublisher
            .dropFirst()
            .first()
            .sink { _ in
                XCTAssertTrue(Thread.isMainThread)
                onMain.fulfill()
            }
            .store(in: &cancellables)

        provider.send(.progress(id: "1#0", receivedBytes: 1, expectedBytes: 2))

        await fulfillment(of: [onMain], timeout: 5)
    }

    func test_handleBackgroundEvents_forwardsToProvider() {
        var called = false

        sut.handleBackgroundEvents { called = true }
        provider.backgroundCompletion?()

        XCTAssertTrue(called)
    }
}

// MARK: - Retry and backoff
extension BookDownloadManagerTests {
    func test_failed_requeuesWithCappedBackoff() async {
        sut.enqueue(makeBook(chapterCount: 1))
        var delays: [TimeInterval] = []

        for attempt in 1...3 {
            provider.send(.failed(id: "1#0", error: .connection))
            await waitUntil { self.pendingRetries.count == 1 }
            XCTAssertEqual(latestStates["1"]?.chapters, [.waiting])
            XCTAssertEqual(provider.startedIDs.count, attempt, "Not restarted before its delay")
            let retry = pendingRetries.removeFirst()
            delays.append(retry.delay)
            retry.run()
            XCTAssertEqual(provider.startedIDs.count, attempt + 1)
        }

        XCTAssertEqual(delays, [30, 120, 600])
    }

    func test_failed_afterTheCap_marksChapterFailed() async {
        sut.enqueue(makeBook(chapterCount: 1))

        await failUntilCapped("1#0")

        XCTAssertEqual(latestStates["1"]?.chapters, [.failed])
        XCTAssertTrue(pendingRetries.isEmpty)
        XCTAssertEqual(startedIDs(ofBook: "1").count, 4)
    }

    func test_failed_otherChaptersKeepDownloading() async {
        sut.enqueue(makeBook(chapterCount: 3))

        provider.send(.failed(id: "1#0", error: .connection))

        await waitUntil { self.provider.startedIDs.contains("1#2") }
        XCTAssertEqual(provider.startedIDs, ["1#0", "1#1", "1#2"])
    }

    func test_retry_failedChapter_restartsItWithAFreshBackoff() async {
        sut.enqueue(makeBook(chapterCount: 1))
        await failUntilCapped("1#0")

        sut.retry(chapterIndex: 0, ofBookID: "1")

        XCTAssertEqual(startedIDs(ofBook: "1").count, 5)
        XCTAssertEqual(latestStates["1"]?.chapters, [.waiting])
        provider.send(.failed(id: "1#0", error: .connection))
        await waitUntil { self.pendingRetries.count == 1 }
        XCTAssertEqual(pendingRetries.first?.delay, 30)
        XCTAssertEqual(latestStates["1"]?.chapters, [.waiting])
    }

    func test_beginThrowing_isRetriedWithBackoff() {
        provider.startError = .invalidUrl

        sut.enqueue(makeBook(chapterCount: 1))

        XCTAssertEqual(pendingRetries.map(\.delay), [30])
        XCTAssertEqual(latestStates["1"]?.chapters, [.waiting])
        provider.startError = nil
        pendingRetries.removeFirst().run()
        XCTAssertEqual(provider.startedIDs, ["1#0", "1#0"])
        XCTAssertTrue(pendingRetries.isEmpty)
    }

    func test_beginThrowing_afterTheCap_marksChapterFailed() {
        provider.startError = .invalidUrl
        sut.enqueue(makeBook(chapterCount: 1))

        while !pendingRetries.isEmpty {
            pendingRetries.removeFirst().run()
        }

        XCTAssertEqual(latestStates["1"]?.chapters, [.failed])
        XCTAssertEqual(provider.startedIDs.count, 4)
    }

    func test_pathSatisfiedAgain_restartsAChapterWaitingToRetry() async {
        sut.enqueue(makeBook(chapterCount: 1))
        provider.send(.failed(id: "1#0", error: .connection))
        await waitUntil { self.pendingRetries.count == 1 }

        path.isOnline = false
        XCTAssertEqual(provider.startedIDs.count, 1, "Going offline starts nothing")
        path.isOnline = true

        XCTAssertEqual(provider.startedIDs, ["1#0", "1#0"])
        pendingRetries.removeFirst().run()
        XCTAssertEqual(provider.startedIDs.count, 2, "The superseded retry does nothing")
    }

    func test_pathSatisfiedAgain_restartsFailedChapters() async {
        sut.enqueue(makeBook(chapterCount: 1))
        await failUntilCapped("1#0")

        path.isOnline = false
        path.isOnline = true

        XCTAssertEqual(startedIDs(ofBook: "1").count, 5)
        XCTAssertEqual(latestStates["1"]?.chapters, [.waiting])
    }

    func test_pathSatisfiedAgain_pausedBook_startsNothing() async {
        sut.enqueue(makeBook(chapterCount: 1))
        provider.send(.failed(id: "1#0", error: .connection))
        await waitUntil { self.pendingRetries.count == 1 }
        sut.pause(bookID: "1")

        path.isOnline = false
        path.isOnline = true

        XCTAssertEqual(provider.startedIDs, ["1#0"])
    }
}

// MARK: - Helpers
private extension BookDownloadManagerTests {
    func makeBook(
        id: String = "1",
        chapterCount: Int = 4,
        chapterBytes: [Int64]? = nil,
        allowsCellular: Bool = true,
        isPaused: Bool = false
    ) -> AudioModel {
        let bytes = chapterBytes ?? Array(repeating: 100, count: chapterCount)
        var book = AudioModel()
        book.title = "Book \(id)"
        book.url = LibriVoxIdentity.bookURL(id: id)
        book.librivoxID = id
        book.allowsCellularDownload = allowsCellular
        book.isDownloadPaused = isPaused
        book.chapters = bytes.indices.map { index in
            ChapterModel(
                title: "Chapter \(index)",
                startTime: Double(index) * 60,
                duration: 60,
                remoteURL: URL(string: "https://archive.org/download/x/ch\(index).mp3"),
                expectedBytes: bytes[index]
            )
        }
        return book
    }

    func importedBook() -> AudioModel {
        var book = AudioModel()
        book.title = "Imported"
        book.url = URL(fileURLWithPath: "/imported.m4b")
        return book
    }

    func writeChapterFile(_ index: Int, of book: AudioModel) throws {
        let id = try XCTUnwrap(book.librivoxID)
        _ = try LibriVoxIdentity.directory(forBookID: id, root: root)
        let url = try XCTUnwrap(LibriVoxIdentity.localFileURL(for: book.chapters[index], bookID: id, root: root))
        try Data([0]).write(to: url)
    }

    func makeTempFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        return url
    }

    /// Waits until `condition` holds, re-checking it on every state emission and provider call.
    func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        _ = sut
        let met = expectation(description: "condition met")
        var fulfilled = false
        let check = {
            guard !fulfilled, condition() else { return }
            fulfilled = true
            met.fulfill()
        }
        observers.append(check)
        check()
        await fulfillment(of: [met], timeout: timeout)
        observers.removeAll()
    }

    /// Fails the chapter's task, then every retry the backoff allows, until it is marked failed.
    func failUntilCapped(_ id: String) async {
        for _ in 1...3 {
            provider.send(.failed(id: id, error: .connection))
            await waitUntil { self.pendingRetries.count == 1 }
            pendingRetries.removeFirst().run()
        }
        provider.send(.failed(id: id, error: .connection))
        await drainEvents()
    }

    func startedIDs(ofBook id: String) -> [String] {
        provider.startedIDs.filter { $0.hasPrefix("\(id)#") }
    }

    /// Returns once every event sent so far has been handled: events are handled in order, so a
    /// progress event for a sentinel book showing up in the state means the earlier ones are done.
    func drainEvents() async {
        drainCount += 1
        if latestStates["sentinel"] == nil {
            sut.enqueue(makeBook(id: "sentinel", chapterCount: 1))
        }
        let received = Int64(drainCount)
        provider.send(.progress(id: "sentinel#0", receivedBytes: received, expectedBytes: 1000))
        await waitUntil {
            self.latestStates["sentinel"]?.chapters == [.downloading(fraction: Double(received) / 1000)]
        }
    }

    func notifyObservers() {
        observers.forEach { $0() }
    }
}

/// Deleting a LibriVox book also cancels its downloads and removes its files.
final class DeleteAudioUseCaseDownloadsTests: XCTestCase {
    private final class MockDeleteAudioRepository: DeleteAudioRepositoryProtocol {
        private(set) var deletedURLs: [URL?] = []

        func execute(url: URL?) { deletedURLs.append(url) }
    }

    func test_execute_libriVoxBook_removesItsDownloads() {
        let repository = MockDeleteAudioRepository()
        var removed: [String] = []
        let sut = DeleteAudioUseCase(
            repository: repository,
            removeDownloads: { removed.append($0) },
            snapshotWriter: MockLibrarySnapshotWriter()
        )
        var book = AudioModel()
        book.url = LibriVoxIdentity.bookURL(id: "200")
        book.librivoxID = "200"

        sut.execute(book)

        XCTAssertEqual(removed, ["200"])
        XCTAssertEqual(repository.deletedURLs, [book.url])
    }

    func test_execute_importedBook_leavesDownloadsAlone() {
        var removed: [String] = []
        let sut = DeleteAudioUseCase(
            repository: MockDeleteAudioRepository(),
            removeDownloads: { removed.append($0) },
            snapshotWriter: MockLibrarySnapshotWriter()
        )
        var book = AudioModel()
        book.url = URL(fileURLWithPath: "/imported.m4b")

        sut.execute(book)

        XCTAssertTrue(removed.isEmpty)
    }

    func test_defaultRemoveDownloads_usesContainerDownloads() {
        let downloads = MockBookDownloadManager()
        DependencyContainer.configure(with: MockDependencyContainer(
            player: MockPlayer(),
            loadAudio: MockLoadAudioUseCase(),
            loadAllAudios: MockLoadAllAudiosUseCase(),
            downloads: downloads
        ))
        defer { DependencyContainer.reset() }
        var book = AudioModel()
        book.librivoxID = "200"

        DeleteAudioUseCase(repository: MockDeleteAudioRepository(), snapshotWriter: MockLibrarySnapshotWriter())
            .execute(book)

        XCTAssertEqual(downloads.removed, ["200"])
    }
}
