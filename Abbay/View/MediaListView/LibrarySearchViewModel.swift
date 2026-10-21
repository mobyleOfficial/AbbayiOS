//
//  LibrarySearchViewModel.swift
//  Abbay
//

import Foundation

enum RemoteStatus: Equatable {
    case idle
    case loading
    case offline
    case failed
    case loaded
}

/// One search over both the Library and LibriVox. Local matching is immediate; the remote request
/// is debounced and skipped entirely while offline.
@MainActor
final class LibrarySearchViewModel: ObservableObject {
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            queryChanged()
        }
    }
    @Published private(set) var localResults: [AudioModel] = []
    @Published private(set) var remoteResults: [LibriVoxBook] = []
    @Published private(set) var remoteStatus: RemoteStatus = .idle

    private let client: LibriVoxClientProtocol
    private let path: NetworkPathProviding
    private let debounce: Duration
    private var library: [AudioModel] = []
    private var fetchedBooks: [LibriVoxBook] = []
    private var searchTask: Task<Void, Never>?
    private var generation = 0

    init(
        client: LibriVoxClientProtocol = LibriVoxClient(),
        path: NetworkPathProviding = NetworkPathMonitor.shared,
        debounce: Duration = .milliseconds(400)
    ) {
        self.client = client
        self.path = path
        self.debounce = debounce
    }

    /// The app's instance. UI tests launched with the stub argument never reach the network.
    static func makeDefault() -> LibrarySearchViewModel {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(LaunchArgument.stubLibriVox) {
            return LibrarySearchViewModel(client: UITestLibriVoxClient(), debounce: .milliseconds(50))
        }
        #endif
        return LibrarySearchViewModel()
    }

    func update(library: [AudioModel]) {
        self.library = library
        applyLocalFilter()
        publishRemote()
    }

    /// The empty-query "Browse" state.
    func loadPopular() async {
        guard trimmedQuery.isEmpty else { return }
        searchTask?.cancel()
        generation += 1
        let current = generation
        guard path.isOnline else {
            setRemote([], status: .offline)
            return
        }
        setRemote([], status: .loading)
        do {
            let books = try await client.popular()
            guard current == generation else { return }
            setRemote(books, status: .loaded)
        } catch {
            guard current == generation else { return }
            setRemote([], status: .failed)
        }
    }

    // MARK: - Private

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func queryChanged() {
        searchTask?.cancel()
        generation += 1
        applyLocalFilter()
        let text = trimmedQuery
        guard !text.isEmpty else {
            setRemote([], status: .idle)
            return
        }
        guard path.isOnline else {
            setRemote([], status: .offline)
            return
        }
        setRemote([], status: .loading)
        let current = generation
        searchTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.runSearch(text, generation: current)
        }
    }

    private func runSearch(_ text: String, generation current: Int) async {
        do {
            let books = try await client.search(text)
            guard current == generation else { return }
            setRemote(books, status: .loaded)
        } catch {
            guard current == generation else { return }
            setRemote([], status: .failed)
        }
    }

    private func setRemote(_ books: [LibriVoxBook], status: RemoteStatus) {
        fetchedBooks = books
        remoteStatus = status
        publishRemote()
    }

    private func publishRemote() {
        let owned = Set(library.compactMap(\.librivoxID))
        remoteResults = fetchedBooks.filter { !owned.contains($0.id) }
    }

    private func applyLocalFilter() {
        let text = trimmedQuery
        guard !text.isEmpty else {
            localResults = []
            return
        }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        localResults = library.filter {
            $0.title.range(of: text, options: options) != nil || $0.artist.range(of: text, options: options) != nil
        }
    }
}
