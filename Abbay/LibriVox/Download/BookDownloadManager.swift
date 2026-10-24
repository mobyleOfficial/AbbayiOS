//
//  BookDownloadManager.swift
//  Abbay
//

import Combine
import Foundation
import NetworkProvider
import os

protocol BookDownloadManagerProtocol: ChapterPrioritizing {
    /// Every known LibriVox book's download state, keyed by librivoxID. Emits on the main thread.
    var statesPublisher: AnyPublisher<[String: BookDownloadState], Never> { get }
    /// Starts the chapters not yet on disk, unless the book is paused.
    func enqueue(_ book: AudioModel)
    func pause(bookID: String)
    func resume(bookID: String)
    /// Cancels every task (dropping resume data) and deletes the book's directory.
    func remove(bookID: String)
    /// At launch: re-attaches to running tasks and restarts the missing chapters.
    func restore()
    func handleBackgroundEvents(completion: @escaping () -> Void)
    /// The listener asked to retry a chapter (typically one that failed): restarts it now, with a
    /// fresh set of automatic retries.
    func retry(chapterIndex: Int, ofBookID id: String)
}

/// Downloads LibriVox books chapter by chapter, at most two chapters per book at a time.
///
/// A chapter that fails is retried after each of `retryDelays` in turn, then marked `.failed`
/// until the listener retries it or the network path becomes satisfied again. Failure counts are
/// persisted (`ChapterFailureStore`), so after a relaunch a chapter that had failed starts again at
/// once but keeps its place in the backoff, and a `.failed` one stays failed.
///
/// Isolation: main-thread confinement. All mutable state is only touched on the main thread:
/// public methods run inline when called on main and hop there otherwise, and provider events are
/// consumed by a `@MainActor` task. So `statesPublisher` always emits on main.
final class BookDownloadManager: BookDownloadManagerProtocol {
    static let sessionIdentifier = "com.edyuto.Abbay.downloads"
    static let maxConcurrentChapters = 2
    /// The wait before each automatic retry of a failing chapter: 30 s, 2 min, 10 min.
    static let retryDelays: [TimeInterval] = [30, 120, 600]
    /// The app's instance. A background session identifier may back only one session per process.
    static let shared = BookDownloadManager()

    fileprivate struct Book {
        let id: String
        let model: AudioModel
        var chapters: [ChapterDownloadState]
        var isPaused: Bool
        /// Chapters waiting for a slot, in start order.
        var queue: [Int] = []
        /// Chapters with a live task.
        var active = Set<Int>()
        /// Failures in a row per chapter, since its last success or fresh start. Mirrored in
        /// `failureStore`.
        var failures: [Int: Int] = [:]
        /// The scheduled retry per chapter. A retry whose token no longer matches was superseded.
        var pendingRetries: [Int: UUID] = [:]
        /// Set by `restore()` until it knows which tasks are still running, so nothing starts twice.
        var isRestoring = false
    }

    private let provider: DownloadProviderProtocol
    private let root: URL
    private let updateFlags: UpdateDownloadFlagsUseCaseProtocol
    private let loadAll: LoadAllAudiosUseCaseProtocol
    private let failureStore: ChapterFailureStore
    private let scheduleRetry: (TimeInterval, @escaping () -> Void) -> Void
    private var pathCancellable: AnyCancellable?
    private let statesSubject = CurrentValueSubject<[String: BookDownloadState], Never>([:])
    private var books: [String: Book] = [:]
    /// In-flight `provider.pause` calls per book, so `resume`/`remove` act after them.
    private var pendingPauses: [String: Task<Void, Never>] = [:]
    /// Task ids whose live task a pause or remove stopped. URLSession reports that cancel after
    /// `pause`/`cancel` return, possibly once a new task with the same id runs, so exactly one
    /// `.cancelledRequest` per id is swallowed.
    private var awaitingCancel = Set<String>()
    private var eventsTask: Task<Void, Never>?

    var statesPublisher: AnyPublisher<[String: BookDownloadState], Never> {
        statesSubject.eraseToAnyPublisher()
    }

    /// - Parameters:
    ///   - path: Its going back online restarts the chapters waiting to retry and the failed ones.
    ///   - failures: Where each chapter's failure count is kept across launches.
    ///   - scheduleRetry: Runs a failed chapter's retry after the given delay, on the main thread.
    init(
        provider: DownloadProviderProtocol = BookDownloadManager.makeBackgroundProvider(),
        root: URL = LibriVoxIdentity.defaultRoot,
        updateFlags: UpdateDownloadFlagsUseCaseProtocol = UpdateDownloadFlagsUseCase(),
        loadAll: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase(),
        path: NetworkPathProviding = NetworkPathMonitor.shared,
        failures: ChapterFailureStore = ChapterFailureStore(),
        scheduleRetry: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, retry in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: retry)
        }
    ) {
        self.provider = provider
        self.root = root
        self.updateFlags = updateFlags
        self.loadAll = loadAll
        failureStore = failures
        self.scheduleRetry = scheduleRetry
        let events = provider.events
        eventsTask = Task { @MainActor [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
        // Only the change back to online: the current value says nothing new.
        pathCancellable = path.onlinePublisher
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                self?.onMain { self?.restartFailing() }
            }
    }

    deinit {
        eventsTask?.cancel()
    }

    static func makeBackgroundProvider() -> DownloadProviderProtocol {
        let resumeData = LibriVoxIdentity.defaultRoot.deletingLastPathComponent()
            .appendingPathComponent("LibriVoxResumeData", isDirectory: true)
        return DownloadProvider(kind: .background(identifier: sessionIdentifier), resumeDataDirectory: resumeData)
    }

    // MARK: - BookDownloadManagerProtocol

    func enqueue(_ book: AudioModel) {
        onMain { [self] in
            guard let id = book.librivoxID, books[id] == nil else { return }
            books[id] = makeBook(book, id: id)
            pump(id)
            publish()
        }
    }

    func pause(bookID: String) {
        onMain { [self] in
            guard var book = books[bookID], !book.isPaused else { return }
            let paused = book.active.sorted()
            awaitingCancel.formUnion(paused.map { Self.taskID(bookID, $0) })
            book.isPaused = true
            book.queue = paused + book.queue
            book.active.removeAll()
            books[bookID] = book
            updateFlags.execute(url: book.model.url, isDownloadPaused: true, allowsCellularDownload: nil)
            publish()
            let provider = provider
            let ids = paused.map { Self.taskID(bookID, $0) }
            let previous = pendingPauses[bookID]
            pendingPauses[bookID] = Task { @MainActor in
                await previous?.value
                for id in ids {
                    await provider.pause(id: id)
                }
            }
        }
    }

    func resume(bookID: String) {
        onMain { [self] in
            guard var book = books[bookID], book.isPaused else { return }
            book.isPaused = false
            books[bookID] = book
            updateFlags.execute(url: book.model.url, isDownloadPaused: false, allowsCellularDownload: nil)
            publish()
            // Resuming before the pause saved its resume data would restart the chapters from zero.
            guard let pending = pendingPauses.removeValue(forKey: bookID) else {
                pump(bookID)
                return
            }
            Task { @MainActor [weak self] in
                await pending.value
                self?.pump(bookID)
                self?.publish()
            }
        }
    }

    func remove(bookID: String) {
        onMain { [self] in
            let book = books.removeValue(forKey: bookID)
            failureStore.removeAll(bookID: bookID)
            awaitingCancel.formUnion(book?.active.map { Self.taskID(bookID, $0) } ?? [])
            try? FileManager.default.removeItem(at: root.appendingPathComponent(bookID, isDirectory: true))
            publish()
            let provider = provider
            let pending = pendingPauses.removeValue(forKey: bookID)
            let ids = book.map { book in book.model.chapters.indices.map { Self.taskID(bookID, $0) } }
            if pending == nil, let ids {
                ids.forEach(provider.cancel(id:))
                return
            }
            Task { @MainActor [self] in
                // After any pause, so the cancel also deletes the resume data that pause saves.
                await pending?.value
                if let ids {
                    ids.forEach(provider.cancel(id:))
                } else {
                    // A book the manager never saw may still have tasks from an earlier launch.
                    let running = await provider.runningIDs().filter { $0.hasPrefix("\(bookID)#") }
                    self.awaitingCancel.formUnion(running)
                    running.forEach(provider.cancel(id:))
                }
            }
        }
    }

    func restore() {
        onMain { [self] in
            // Known right away: a relaunched background session delivers the downloads that
            // finished while the app was dead as soon as it exists, and those need their book.
            var restored: [String] = []
            for model in loadAll.execute() {
                guard let id = model.librivoxID, books[id] == nil else { continue }
                var book = makeBook(model, id: id)
                book.isRestoring = true
                books[id] = book
                restored.append(id)
            }
            publish()
            Task { @MainActor [weak self] in
                guard let self else { return }
                var running = await provider.runningIDs()
                // A Wi-Fi-only book's task started before #134 may still use a hotspot or Low Data
                // Mode, and a running task's request can't change: restart it from scratch. Marked
                // before cancelling, so its cancel is swallowed whenever it arrives.
                let metered = await provider.runningIDsAllowingMeteredNetworks()
                let restarted = metered.filter { taskID in
                    guard case let (bookID, _)? = locate(taskID), restored.contains(bookID) else { return false }
                    return books[bookID]?.model.allowsCellularDownload == false
                }
                if !restarted.isEmpty {
                    Log.downloads.info("restarting \(restarted.count, privacy: .public) tasks allowed on metered networks")
                    awaitingCancel.formUnion(restarted)
                    running.subtract(restarted)
                    await provider.cancel(ids: restarted)
                }
                for id in restored {
                    guard var book = books[id] else { continue }
                    let attached = book.queue.filter { running.contains(Self.taskID(id, $0)) }
                    book.active.formUnion(attached)
                    book.queue.removeAll(where: attached.contains)
                    book.isRestoring = false
                    books[id] = book
                    pump(id)
                }
                publish()
            }
        }
    }

    func handleBackgroundEvents(completion: @escaping () -> Void) {
        provider.handleBackgroundEvents(completion: completion)
    }

    // MARK: - ChapterPrioritizing

    /// The listener needs this chapter now, so a failed one or one waiting out its backoff starts
    /// too, with a fresh set of retries.
    func prioritize(chapterIndex: Int, ofBookID id: String) {
        onMain { [self] in
            guard var book = books[id], book.chapters.indices.contains(chapterIndex),
                  book.chapters[chapterIndex] != .downloaded, !book.active.contains(chapterIndex) else { return }
            resetFailures(of: chapterIndex, in: &book)
            book.queue.removeAll { $0 == chapterIndex }
            book.queue.insert(chapterIndex, at: 0)
            books[id] = book
            pump(id)
            publish()
        }
    }

    func retry(chapterIndex: Int, ofBookID id: String) {
        prioritize(chapterIndex: chapterIndex, ofBookID: id)
    }
}

// MARK: - Events
private extension BookDownloadManager {
    func handle(_ event: DownloadEvent) {
        switch event {
        case let .progress(id, received, expected):
            progress(id: id, received: received, expected: expected)
        case let .finished(id, location):
            finish(id: id, location: location)
        case let .failed(id, error):
            fail(id: id, error: error)
        }
        publish()
    }

    func progress(id: String, received: Int64, expected: Int64?) {
        guard case let (bookID, index)? = locate(id), var book = books[bookID],
              book.chapters[index] != .downloaded else { return }
        let total = expected ?? book.model.chapters[index].expectedBytes
        book.chapters[index] = .downloading(fraction: total > 0 ? min(Double(received) / Double(total), 1) : 0)
        books[bookID] = book
    }

    func finish(id: String, location: URL) {
        // It finished before the pause or remove could stop it, so no cancel will follow.
        awaitingCancel.remove(id)
        guard case let (bookID, index)? = locate(id), var book = books[bookID],
              let destination = LibriVoxIdentity.localFileURL(
                  for: book.model.chapters[index], bookID: bookID, root: root
              )
        else {
            try? FileManager.default.removeItem(at: location)
            return
        }
        do {
            _ = try LibriVoxIdentity.directory(forBookID: bookID, root: root)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            let error = error as NSError
            Log.downloads.error(
                """
                chapter \(index, privacy: .public): moving the file failed: \
                \(error.domain, privacy: .public) \(error.code, privacy: .public)
                """
            )
            try? FileManager.default.removeItem(at: location)
            markFailed(index, bookID: bookID)
            pump(bookID)
            return
        }
        book.active.remove(index)
        book.queue.removeAll { $0 == index }
        book.chapters[index] = .downloaded
        resetFailures(of: index, in: &book)
        books[bookID] = book
        pump(bookID)
    }

    func fail(id: String, error: NetworkError) {
        // The end of a task a pause or remove stopped; a new task with the same id may already run.
        guard awaitingCancel.remove(id) == nil else { return }
        guard case let (bookID, index)? = locate(id), var book = books[bookID], book.active.contains(index) else {
            // A chapter with no live task: nothing to update.
            return
        }
        guard error != .cancelledRequest else {
            // Not a failure: the system cancelled the task (e.g. a force quit). Requeue in chapter
            // order without restarting now; the next free slot or `restore()` resumes it.
            book.active.remove(index)
            book.chapters[index] = .waiting
            book.queue.insert(index, at: book.queue.firstIndex { $0 > index } ?? book.queue.endIndex)
            books[bookID] = book
            return
        }
        markFailed(index, bookID: bookID)
        pump(bookID)
    }

    func markFailed(_ index: Int, bookID: String) {
        guard var book = books[bookID] else { return }
        recordFailure(index, in: &book)
        books[bookID] = book
    }

    /// Puts the chapter back to waiting with its next backoff retry scheduled, or marks it failed
    /// once `retryDelays` are used up.
    func recordFailure(_ index: Int, in book: inout Book) {
        book.active.remove(index)
        let failures = book.failures[index, default: 0] + 1
        book.failures[index] = failures
        failureStore.set(failures, bookID: book.id, chapter: book.model.chapters[index])
        // Once the retries are used up the chapter's row shows "Failed · Retry": no notice.
        Log.downloads.error("chapter \(index, privacy: .public) failed, attempt \(failures, privacy: .public)")
        guard failures <= Self.retryDelays.count else {
            book.pendingRetries[index] = nil
            book.chapters[index] = .failed
            return
        }
        book.chapters[index] = .waiting
        let token = UUID()
        book.pendingRetries[index] = token
        let bookID = book.id
        scheduleRetry(Self.retryDelays[failures - 1]) { [weak self] in
            self?.retry(index, bookID: bookID, token: token)
        }
    }

    func retry(_ index: Int, bookID: String, token: UUID) {
        guard var book = books[bookID], book.pendingRetries[index] == token else { return }
        book.pendingRetries[index] = nil
        guard book.chapters[index] != .downloaded, !book.active.contains(index) else {
            books[bookID] = book
            return
        }
        book.queue.removeAll { $0 == index }
        book.queue.insert(index, at: 0)
        books[bookID] = book
        pump(bookID)
        publish()
    }

    /// The network is back: chapters waiting out a backoff or failed for good were most likely
    /// failing for lack of it, so they restart now, in chapter order, with fresh retries.
    func restartFailing() {
        for (id, var book) in books {
            let failing = book.chapters.indices.filter { index in
                book.chapters[index] == .failed || book.pendingRetries[index] != nil
            }
            guard !failing.isEmpty else { continue }
            for index in failing {
                resetFailures(of: index, in: &book)
                book.queue.removeAll { $0 == index }
            }
            book.queue.insert(contentsOf: failing, at: 0)
            books[id] = book
            pump(id)
        }
        publish()
    }
}

// MARK: - Helpers
private extension BookDownloadManager {
    static func taskID(_ bookID: String, _ index: Int) -> String {
        "\(bookID)#\(index)"
    }

    /// Splits `"<bookID>#<index>"`, for a known book and a valid chapter index.
    func locate(_ taskID: String) -> (bookID: String, index: Int)? {
        guard let separator = taskID.lastIndex(of: "#"),
              let index = Int(taskID[taskID.index(after: separator)...]) else { return nil }
        let bookID = String(taskID[..<separator])
        guard books[bookID]?.chapters.indices.contains(index) == true else { return nil }
        return (bookID, index)
    }

    /// The book as its files on disk and its persisted failure counts leave it: a chapter that used
    /// up its retries is `.failed` and not queued; one that failed fewer times is queued with its
    /// count, so its next failure waits the next delay rather than the first.
    func makeBook(_ model: AudioModel, id: String) -> Book {
        var failures: [Int: Int] = [:]
        let chapters: [ChapterDownloadState] = model.chapters.enumerated().map { index, chapter in
            if LibriVoxIdentity.isDownloaded(chapter, bookID: id, root: root) {
                failureStore.set(0, bookID: id, chapter: chapter)
                return .downloaded
            }
            let failed = failureStore.failures(bookID: id, chapter: chapter)
            if failed > 0 { failures[index] = failed }
            return failed > Self.retryDelays.count ? .failed : .waiting
        }
        let queue = chapters.indices.filter { chapters[$0] == .waiting && model.chapters[$0].remoteURL != nil }
        return Book(
            id: id,
            model: model,
            chapters: chapters,
            isPaused: model.isDownloadPaused,
            queue: queue,
            failures: failures
        )
    }

    /// Starts queued chapters in order until the book has `maxConcurrentChapters` running.
    func pump(_ bookID: String) {
        guard var book = books[bookID], !book.isPaused, !book.isRestoring else { return }
        while book.active.count < Self.maxConcurrentChapters, !book.queue.isEmpty {
            let index = book.queue.removeFirst()
            guard book.chapters[index] != .downloaded else { continue }
            if begin(index, of: book) {
                book.active.insert(index)
            } else {
                // Counted like a failed task, so it is retried rather than left waiting for good.
                recordFailure(index, in: &book)
            }
        }
        books[bookID] = book
    }

    /// Forgets the chapter's failures and any scheduled retry, and shows a failed one as waiting.
    func resetFailures(of index: Int, in book: inout Book) {
        book.failures[index] = nil
        failureStore.set(0, bookID: book.id, chapter: book.model.chapters[index])
        book.pendingRetries[index] = nil
        if book.chapters[index] == .failed {
            book.chapters[index] = .waiting
        }
    }

    /// Resumes from saved resume data when there is some, else starts from scratch.
    /// `allowsCellularDownload == false` also keeps the task off Personal Hotspot and Low Data Mode.
    func begin(_ index: Int, of book: Book) -> Bool {
        let id = Self.taskID(book.id, index)
        let allowsCellular = book.model.allowsCellularDownload
        do {
            try provider.resume(id: id, allowsCellularAccess: allowsCellular)
            return true
        } catch NetworkError.invalidParams {
            // No resume data: start below.
        } catch {
            return false
        }
        guard let url = book.model.chapters[index].remoteURL else { return false }
        do {
            let request = NetworkRequest(endpoint: url.absoluteString)
            try provider.start(request, id: id, allowsCellularAccess: allowsCellular)
            return true
        } catch {
            return false
        }
    }

    func publish() {
        statesSubject.send(books.mapValues { book in
            BookDownloadState(
                chapters: book.chapters,
                expectedBytes: book.model.chapters.map(\.expectedBytes),
                isPaused: book.isPaused
            )
        })
    }

    func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
