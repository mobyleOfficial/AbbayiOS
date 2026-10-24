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

/// Whether the path is Wi-Fi in Low Data Mode (`NetworkPathSnapshot.isLowDataModeWiFi`). Its own
/// observable, so only the views that explain a hold depend on it.
@Observable
final class LowDataModeStatus {
    private(set) var isOn = false

    fileprivate func update(_ isOn: Bool) {
        guard isOn != self.isOn else { return }
        self.isOn = isOn
    }
}

/// The one app-wide download source. It subscribes to the manager's `statesPublisher` exactly once
/// and fans the map out into one observable entry per book, so one book's progress only reaches
/// the views reading that book's entry.
@MainActor
final class DownloadStateStore {
    private let downloads: BookDownloadManagerProtocol
    /// Read by the screens that show a book's download status, to explain a Low Data Mode hold.
    let lowDataMode = LowDataModeStatus()
    // Not observed: asking for an entry must never make a view depend on the whole map.
    @ObservationIgnored private var entries: [String: BookDownloadEntry] = [:]
    @ObservationIgnored private var latest: [String: BookDownloadState] = [:]
    private var cancellable: AnyCancellable?
    private var lowDataModeCancellable: AnyCancellable?

    /// `nonisolated` so `DependencyContainer` can build it from any context; deliveries are moved
    /// onto the main actor in `onMain`.
    nonisolated init(downloads: BookDownloadManagerProtocol, path: NetworkPathProviding = NetworkPathMonitor.shared) {
        self.downloads = downloads
        cancellable = downloads.statesPublisher.sink { [weak self] states in
            Self.onMain { self?.receive(states) }
        }
        let lowDataMode = lowDataMode
        lowDataModeCancellable = path.lowDataModePublisher.sink { isOn in
            Self.onMain { lowDataMode.update(isOn) }
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

    /// The book's download is waiting only because the Wi-Fi is in Low Data Mode: it is a
    /// Wait-for-Wi-Fi book (`allowsCellular` false), still downloading and not paused. Reads the
    /// book's entry and `lowDataMode`, so a view calling it follows both.
    func isHeldByLowDataMode(bookID: String, allowsCellular: Bool) -> Bool {
        Self.isHeldByLowDataMode(
            entry(for: bookID).state,
            allowsCellular: allowsCellular,
            isLowDataMode: lowDataMode.isOn
        )
    }

    nonisolated static func isHeldByLowDataMode(
        _ state: BookDownloadState?,
        allowsCellular: Bool,
        isLowDataMode: Bool
    ) -> Bool {
        guard let state, !state.isComplete, !state.isPaused else { return false }
        return isLowDataMode && !allowsCellular
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
