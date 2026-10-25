//
//  LibriVoxSearchViewModel.swift
//  Abbay
//

import Foundation
import Observation

/// Where a LibriVox request stands, for the Search tab's states.
enum RemoteStatus: Equatable {
    case idle
    case loading
    case offline
    case failed
    case loaded
}

/// The LibriVox search. The request is debounced and skipped entirely while offline.
@MainActor
@Observable
final class LibriVoxSearchViewModel {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            queryChanged()
        }
    }
    private(set) var results: [LibriVoxBook] = []
    private(set) var popular: [LibriVoxBook] = []
    private(set) var status: RemoteStatus = .idle

    @ObservationIgnored private let client: LibriVoxClientProtocol
    @ObservationIgnored private let path: NetworkPathProviding
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// Popular is not discarded by typing: only a newer `loadPopular` supersedes it.
    @ObservationIgnored private var popularToken = 0
    @ObservationIgnored private var popularInFlight = false

    init(
        client: LibriVoxClientProtocol = LibriVoxClient(),
        path: NetworkPathProviding = NetworkPathMonitor.shared,
        debounce: Duration = .milliseconds(400)
    ) {
        self.client = client
        self.path = path
        self.debounce = debounce
    }

    /// The app's instance. UI tests launched with the stub argument never reach the network, and a
    /// stubbed path (`-stubPathOffline`) decides whether it is online.
    static func makeDefault() -> LibriVoxSearchViewModel {
        LibriVoxSearchViewModel(
            client: DebugOverrides.libriVoxClient() ?? LibriVoxClient(),
            path: NetworkPathMonitor.app,
            debounce: DebugOverrides.searchDebounce() ?? .milliseconds(400)
        )
    }

    /// The empty-query "Popular" state. The client is asked even offline, because it serves its
    /// cached list without the network; "offline" shows only when there is nothing to show.
    func loadPopular() async {
        guard trimmedQuery.isEmpty else { return }
        searchTask?.cancel()
        generation += 1
        popularToken += 1
        let token = popularToken
        let isOnline = path.isOnline
        // A refresh keeps showing the list it already has instead of swapping it for a spinner.
        let hadPopular = !popular.isEmpty
        if !hadPopular { set(status: .loading) }
        popularInFlight = true
        defer { if token == popularToken { popularInFlight = false } }
        do {
            let books = try await client.popular()
            guard token == popularToken else { return }
            // Nothing to show is a failure too: the "Popular" heading over a blank grid says nothing.
            guard !books.isEmpty else {
                if !hadPopular { settlePopular(isOnline ? .failed : .offline) }
                return
            }
            set(popular: books)
            settlePopular(.loaded)
        } catch {
            guard token == popularToken else { return }
            if !hadPopular { settlePopular(isOnline ? .failed : .offline) }
        }
    }

    // MARK: - Private

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func queryChanged() {
        searchTask?.cancel()
        generation += 1
        set(results: [])
        let text = trimmedQuery
        guard !text.isEmpty else {
            if !popular.isEmpty {
                set(status: .loaded)
            } else {
                set(status: popularInFlight ? .loading : .idle)
            }
            return
        }
        guard path.isOnline else {
            set(status: .offline)
            return
        }
        set(status: .loading)
        let current = generation
        searchTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.runSearch(text, generation: current)
        }
    }

    /// The popular outcome becomes the status only while the field is empty; otherwise the search owns it.
    private func settlePopular(_ value: RemoteStatus) {
        guard trimmedQuery.isEmpty else { return }
        set(status: value)
    }

    private func runSearch(_ text: String, generation current: Int) async {
        do {
            let books = try await client.search(text)
            guard current == generation else { return }
            set(results: books)
            set(status: .loaded)
        } catch {
            guard current == generation else { return }
            set(status: .failed)
        }
    }

    // Observation notifies on every set, so assign only when the value changes.
    private func set(results value: [LibriVoxBook]) {
        if results != value { results = value }
    }

    private func set(popular value: [LibriVoxBook]) {
        if popular != value { popular = value }
    }

    private func set(status value: RemoteStatus) {
        if status != value { status = value }
    }
}
