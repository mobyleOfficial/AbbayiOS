//
//  DownloadStateStore.swift
//  Abbay
//

import Combine
import Foundation
import Observation

/// One book's download state. `nil` means untracked or complete, matching what rows show today.
/// Observation notifies on every set, even with an equal value, so `update` assigns only on change.
@Observable
final class BookDownloadEntry {
    private(set) var state: BookDownloadState?

    fileprivate func update(_ newState: BookDownloadState?) {
        guard newState != state else { return }
        state = newState
    }
}

/// What the path holds a Wait-for-Wi-Fi book for (`NetworkPathSnapshot.hold`). Its own observable,
/// so only the views that explain a hold depend on it.
@Observable
final class NetworkHoldStatus {
    private(set) var hold: NetworkHold?

    fileprivate func update(_ hold: NetworkHold?) {
        guard hold != self.hold else { return }
        self.hold = hold
    }
}

/// The one app-wide download source. It subscribes to the manager's `statesPublisher` exactly once
/// and fans the map out into one observable entry per book, so one book's progress only reaches
/// the views reading that book's entry.
@MainActor
final class DownloadStateStore {
    private let downloads: BookDownloadManagerProtocol
    /// Read by the screens that show a book's download status, to explain a hold.
    let networkHold = NetworkHoldStatus()
    // Not observed: asking for an entry must never make a view depend on the whole map.
    @ObservationIgnored private var entries: [String: BookDownloadEntry] = [:]
    @ObservationIgnored private var latest: [String: BookDownloadState] = [:]
    private var cancellable: AnyCancellable?
    private var holdCancellable: AnyCancellable?

    /// `nonisolated` so `DependencyContainer` can build it from any context; deliveries are moved
    /// onto the main actor in `onMain`.
    nonisolated init(downloads: BookDownloadManagerProtocol, path: NetworkPathProviding = NetworkPathMonitor.shared) {
        self.downloads = downloads
        cancellable = downloads.statesPublisher.sink { [weak self] states in
            Self.onMain { self?.receive(states) }
        }
        let networkHold = networkHold
        holdCancellable = path.holdPublisher.sink { hold in
            Self.onMain { networkHold.update(hold) }
        }
    }

    /// The same instance for a given id, created on first ask from the latest known state.
    func entry(for bookID: String) -> BookDownloadEntry {
        if let existing = entries[bookID] { return existing }
        let entry = BookDownloadEntry()
        entry.update(Self.visibleState(latest[bookID]))
        entries[bookID] = entry
        return entry
    }

    /// Why the book's download is waiting on this path, if the path is the reason: it is a
    /// Wait-for-Wi-Fi book (`allowsCellular` false), still downloading and not paused, and the
    /// path is cellular, a hotspot or Low Data Mode. Reads the book's entry, and `networkHold` only
    /// while the book is downloading, so an idle row doesn't follow the path.
    func hold(bookID: String, allowsCellular: Bool) -> NetworkHold? {
        Self.hold(entry(for: bookID).state, allowsCellular: allowsCellular) { networkHold.hold }
    }

    nonisolated static func hold(
        _ state: BookDownloadState?,
        allowsCellular: Bool,
        pathHold: () -> NetworkHold?
    ) -> NetworkHold? {
        guard let state, !state.isComplete, !state.isPaused, !allowsCellular else { return nil }
        return pathHold()
    }

    func pause(bookID: String) { downloads.pause(bookID: bookID) }
    func resume(bookID: String) { downloads.resume(bookID: bookID) }
    func retry(chapterIndex: Int, bookID: String) { downloads.retry(chapterIndex: chapterIndex, ofBookID: bookID) }

    private func receive(_ states: [String: BookDownloadState]) {
        latest = states
        for (id, entry) in entries {
            entry.update(Self.visibleState(states[id]))
        }
    }

    private nonisolated static func visibleState(_ state: BookDownloadState?) -> BookDownloadState? {
        guard let state, !state.isComplete else { return nil }
        return state
    }

    /// Runs synchronously on the main thread (the manager emits there), hops to it otherwise.
    private nonisolated static func onMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(work) }
        }
    }
}
