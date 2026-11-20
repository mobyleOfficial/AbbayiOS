//
//  LibriVoxDetailViewModel.swift
//  Abbay
//

import Foundation
import os

@MainActor
final class LibriVoxDetailViewModel: ObservableObject {
    @Published private(set) var details: LibriVoxBookDetails?
    /// True while the page shows archive.org's version and LibriVox's chapter titles and
    /// description are still on their way (#258): those shimmer meanwhile.
    @Published private(set) var isAwaitingLibriVox = false
    /// Download was tapped while `isAwaitingLibriVox`: it starts once the final chapters are in,
    /// so the saved book never keeps the file-name titles LibriVox was about to replace.
    @Published private(set) var isDownloadPending = false
    /// Stream was tapped while `isAwaitingLibriVox`, for the same reason as `isDownloadPending`.
    @Published private(set) var isStreamPending = false
    @Published private(set) var loadFailed = false
    /// Non-nil once Download or Stream saved the book (or it was already in the library).
    @Published private(set) var addedBook: AudioModel?
    @Published var isShowingCellularAlert = false

    let book: LibriVoxBook
    private let client: LibriVoxClientProtocol
    /// Where a confirmed download is enqueued. Its states are read through `downloadStates`.
    private let downloads: BookDownloadManagerProtocol
    private let downloadStates: DownloadStateStore
    private let saveAudio: SaveAudioUseCaseProtocol
    /// Download on a book added with Stream (#340) clears its stream-only flag.
    private let updateFlags: UpdateDownloadFlagsUseCaseProtocol
    private let path: NetworkPathProviding
    /// Read when Download is tapped, so a change in Settings applies to the next download.
    private let cellularPreference: () -> CellularDownloadPreference
    /// Remembers the listed language for the saved book (a code such as `en`), as a hint for
    /// read-along. Kept whether or not read-along is on: it is a hint, not text.
    private let recordLanguage: (String, URL?) -> Void
    private let onAdded: (AudioModel) -> Void
    /// Presents the details screen, the same presentation a Library row opens.
    private let openPlayer: (AudioModel) -> Void
    private let noticeReporter: NoticeReporting
    private var isStarting = false

    init(
        book: LibriVoxBook,
        client: LibriVoxClientProtocol,
        downloads: BookDownloadManagerProtocol,
        downloadStates: DownloadStateStore,
        saveAudio: SaveAudioUseCaseProtocol,
        path: NetworkPathProviding,
        loadAudio: LoadAudioUseCaseProtocol = LoadAudioUseCase(),
        updateFlags: UpdateDownloadFlagsUseCaseProtocol = UpdateDownloadFlagsUseCase(),
        cellularPreference: @escaping () -> CellularDownloadPreference = { .ask },
        recordLanguage: @escaping (String, URL?) -> Void = { code, url in
            guard DependencyContainer.isConfigured else { return }
            DependencyContainer.shared.settings.setReadAlongLanguage(code, for: url)
        },
        noticeReporter: NoticeReporting = NoticeCenter.shared,
        onAdded: @escaping (AudioModel) -> Void,
        openPlayer: @escaping (AudioModel) -> Void
    ) {
        self.book = book
        self.client = client
        self.downloads = downloads
        self.downloadStates = downloadStates
        self.saveAudio = saveAudio
        self.updateFlags = updateFlags
        self.path = path
        self.cellularPreference = cellularPreference
        self.recordLanguage = recordLanguage
        self.noticeReporter = noticeReporter
        self.onAdded = onAdded
        self.openPlayer = openPlayer
        // A book already in the library shows Play and its progress, and is never added again.
        addedBook = loadAudio.execute(url: LibriVoxIdentity.bookURL(id: book.id))
    }

    /// Non-nil only while this book's download is incomplete, matching `PlayerViewModel`, so a
    /// finished book shows no per-chapter status and no progress bar on either screen. Read from
    /// the app-wide store's entry for this book (observable), not from a sink of its own, so the
    /// download manager keeps one subscriber; a view reading this re-renders on this book only.
    var downloadState: BookDownloadState? {
        downloadStates.entry(for: book.id).state
    }

    /// Once added as a Wait-for-Wi-Fi book, why its download is waiting on this network, if it is:
    /// the chapter list says so.
    var downloadHold: NetworkHold? {
        guard let addedBook else { return nil }
        return downloadStates.hold(bookID: book.id, allowsCellular: addedBook.allowsCellularDownload)
    }

    /// Download is offered: the book isn't in the library yet, or it was added with Stream (#340).
    var canDownload: Bool {
        addedBook.map(\.isStreamOnly) ?? true
    }

    /// The size shown on the page and used by the cellular policy.
    var totalBytes: Int64 { details?.totalBytes ?? 0 }

    /// Shows archive.org's version as soon as it arrives, then LibriVox's.
    func load() async {
        loadFailed = false
        defer {
            isAwaitingLibriVox = false
            if isDownloadPending {
                isDownloadPending = false
                if details != nil { downloadTapped() }
            } else if isStreamPending {
                isStreamPending = false
                if details != nil { streamTapped() }
            }
        }
        do {
            details = try await client.details(for: book) { [weak self] preview in
                guard let self else { return }
                details = preview
                isAwaitingLibriVox = true
            }
        } catch {
            guard !Task.isCancelled, details == nil else { return }
            loadFailed = true
        }
    }

    func downloadTapped() {
        guard let details, canDownload, !isStarting, !isStreamPending else { return }
        if isAwaitingLibriVox {
            isDownloadPending = true
            return
        }
        let decision = CellularDownloadPolicy.decide(
            totalBytes: details.totalBytes,
            isMetered: path.isMetered,
            preference: cellularPreference()
        )
        switch decision {
        case let .proceed(allowsCellular):
            start(details, allowsCellular: allowsCellular)
        case .askUser:
            isShowingCellularAlert = true
        }
    }

    /// "Continue" allows cellular for this book; "Wait for Wi-Fi" starts it Wi-Fi only.
    func confirmCellular(continue shouldContinue: Bool) {
        isShowingCellularAlert = false
        guard let details, canDownload, !isStarting else { return }
        start(details, allowsCellular: shouldContinue)
    }

    /// Adds the book without downloading it (#340) and plays it: the player streams every chapter.
    /// No size check, as streaming ignores the cellular setting.
    func streamTapped() {
        guard let details, addedBook == nil, !isStarting, !isDownloadPending else { return }
        if isAwaitingLibriVox {
            isStreamPending = true
            return
        }
        save(details, allowsCellular: true, isStreamOnly: true) { [weak self] in self?.play() }
    }

    /// A chapter's "Failed · Retry" status: restarts its download now.
    func retryChapter(_ index: Int) {
        downloads.retry(chapterIndex: index, ofBookID: book.id)
    }

    /// Starts the book and opens the details screen, where pause, seek and chapters live.
    func play() {
        guard var model = addedBook else { return }
        DependencyContainer.shared.player.play(&model)
        openPlayer(model)
    }

    private func start(_ details: LibriVoxBookDetails, allowsCellular: Bool) {
        guard var model = addedBook else {
            save(details, allowsCellular: allowsCellular, isStreamOnly: false) { [weak self] in
                guard let self, let addedBook else { return }
                downloads.enqueue(addedBook)
            }
            return
        }
        // A book added with Stream: downloaded from now on, like one added with Download.
        updateFlags.execute(
            url: model.url,
            isDownloadPaused: nil,
            allowsCellularDownload: allowsCellular,
            isStreamOnly: false
        )
        model.allowsCellularDownload = allowsCellular
        model.isStreamOnly = false
        addedBook = model
        onAdded(model)
        downloads.enqueue(model)
    }

    /// Saves the book to the library, then runs `then` (start its download, or play it).
    private func save(
        _ details: LibriVoxBookDetails,
        allowsCellular: Bool,
        isStreamOnly: Bool,
        then: @escaping () -> Void
    ) {
        isStarting = true
        Task { [weak self] in
            guard let self else { return }
            defer { isStarting = false }
            let cover = await client.coverData(for: book)
            var model = details.audioModel(imageData: cover)
            model.allowsCellularDownload = allowsCellular
            model.isStreamOnly = isStreamOnly
            do {
                try saveAudio.execute(model)
            } catch {
                // Download would otherwise do nothing at all (#115).
                let error = error as NSError
                Log.downloads.error(
                    "saving the book failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)"
                )
                noticeReporter.report(.saveFailed)
                return
            }
            if let code = ReadAlongLanguage.languageCode(fromLibriVox: details.book.language) {
                recordLanguage(code, model.url)
            }
            addedBook = model
            onAdded(model)
            then()
        }
    }
}
