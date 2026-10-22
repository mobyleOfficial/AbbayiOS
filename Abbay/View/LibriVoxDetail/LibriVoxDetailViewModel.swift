//
//  LibriVoxDetailViewModel.swift
//  Abbay
//

import Combine
import Foundation

@MainActor
final class LibriVoxDetailViewModel: ObservableObject {
    @Published private(set) var details: LibriVoxBookDetails?
    @Published private(set) var loadFailed = false
    /// Non-nil once Download was confirmed and the book was saved.
    @Published private(set) var addedBook: AudioModel?
    @Published private(set) var downloadState: BookDownloadState?
    @Published var isShowingCellularAlert = false
    /// Drives the full player sheet, the same one a Library row opens.
    @Published var isShowingPlayer = false

    let book: LibriVoxBook
    private let client: LibriVoxClientProtocol
    private let downloads: BookDownloadManagerProtocol
    private let saveAudio: SaveAudioUseCaseProtocol
    private let path: NetworkPathProviding
    private let onAdded: (AudioModel) -> Void
    private var isStarting = false
    private var cancellables = Set<AnyCancellable>()

    init(
        book: LibriVoxBook,
        client: LibriVoxClientProtocol,
        downloads: BookDownloadManagerProtocol,
        saveAudio: SaveAudioUseCaseProtocol,
        path: NetworkPathProviding,
        loadAudio: LoadAudioUseCaseProtocol = LoadAudioUseCase(),
        onAdded: @escaping (AudioModel) -> Void
    ) {
        self.book = book
        self.client = client
        self.downloads = downloads
        self.saveAudio = saveAudio
        self.path = path
        self.onAdded = onAdded
        // A book already in the library shows Play and its progress, and is never added again.
        addedBook = loadAudio.execute(url: LibriVoxIdentity.bookURL(id: book.id))
        downloads.statesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] states in
                guard let self else { return }
                downloadState = states[self.book.id]
            }
            .store(in: &cancellables)
    }

    /// The size shown on the page and used by the cellular policy.
    var totalBytes: Int64 { details?.totalBytes ?? 0 }

    func load() async {
        loadFailed = false
        do {
            details = try await client.details(for: book)
        } catch {
            guard !Task.isCancelled else { return }
            loadFailed = true
        }
    }

    func downloadTapped() {
        guard let details, addedBook == nil, !isStarting else { return }
        switch CellularDownloadPolicy.decide(totalBytes: details.totalBytes, isCellular: path.isCellular) {
        case let .proceed(allowsCellular):
            start(details, allowsCellular: allowsCellular)
        case .askUser:
            isShowingCellularAlert = true
        }
    }

    /// "Continue" allows cellular for this book; "Wait for Wi-Fi" starts it Wi-Fi only.
    func confirmCellular(continue shouldContinue: Bool) {
        isShowingCellularAlert = false
        guard let details, addedBook == nil, !isStarting else { return }
        start(details, allowsCellular: shouldContinue)
    }

    /// Starts the book and opens the player sheet, where pause, seek and chapters live.
    func play() {
        guard var model = addedBook else { return }
        DependencyContainer.shared.player.play(&model)
        isShowingPlayer = true
    }

    private func start(_ details: LibriVoxBookDetails, allowsCellular: Bool) {
        isStarting = true
        Task { [weak self] in
            guard let self else { return }
            let cover = await client.coverData(for: book)
            var model = details.audioModel(imageData: cover)
            model.allowsCellularDownload = allowsCellular
            do {
                try saveAudio.execute(model)
            } catch {
                isStarting = false
                return
            }
            addedBook = model
            onAdded(model)
            downloads.enqueue(model)
        }
    }
}
