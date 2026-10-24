//
//  SettingsViewModel.swift
//  Abbay
//

import Foundation

/// What the Settings screen needs from the library, as closures so the screen's model is testable
/// without Core Data. The root builds it over the library model, so a delete goes through the same
/// path as a swipe (unloading the playing book, closing its details screen, rewriting Siri's
/// snapshot).
struct SettingsLibrary {
    var books: @MainActor () -> [AudioModel]
    var downloadState: @MainActor (String) -> BookDownloadState?
    var delete: @MainActor ([AudioModel]) -> Void
}

/// The Settings screen's model. The settings themselves are `AppSettings`, bound directly; this
/// adds what has to be computed: the space LibriVox downloads take, the books "Delete finished
/// downloads" removes, the version line and the Siri & audio status.
@MainActor
final class SettingsViewModel: ObservableObject {
    let settings: AppSettings
    private let library: SettingsLibrary
    private let measureBytes: () async -> Int64
    private let audioUnavailable: () -> Bool
    private let bundleInfo: [String: Any]

    /// Nil until measured.
    @Published private(set) var bytesUsed: Int64?
    @Published private(set) var finishedBooks: [AudioModel] = []
    @Published var isConfirmingDelete = false

    init(
        settings: AppSettings,
        library: SettingsLibrary,
        measureBytes: @escaping () async -> Int64 = {
            await Task.detached(priority: .utility) { DownloadHousekeeping.bytesUsed() }.value
        },
        isAudioUnavailable: @escaping () -> Bool = LaunchStateFlag.isUnavailable,
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) {
        self.settings = settings
        self.library = library
        self.measureBytes = measureBytes
        self.audioUnavailable = isAudioUnavailable
        self.bundleInfo = bundleInfo
    }

    // MARK: - Downloads

    var canDeleteFinished: Bool { !finishedBooks.isEmpty }

    /// What deleting the finished books frees, from their download sizes.
    var finishedBytes: Int64 {
        finishedBooks.map(\.totalBytes).reduce(0, +)
    }

    /// Re-reads the library (positions move while the screen is closed) and re-measures the disk.
    func refresh() async {
        let books = library.books()
        var states: [String: BookDownloadState] = [:]
        for id in books.compactMap(\.librivoxID) {
            states[id] = library.downloadState(id)
        }
        finishedBooks = DownloadHousekeeping.finishedDownloads(in: books, state: { states[$0] })
        bytesUsed = await measureBytes()
    }

    func askToDeleteFinished() {
        guard canDeleteFinished else { return }
        isConfirmingDelete = true
    }

    func confirmDeleteFinished() async {
        isConfirmingDelete = false
        let books = finishedBooks
        guard !books.isEmpty else { return }
        library.delete(books)
        await refresh()
    }

    // MARK: - About

    /// "1.4.0 (52)": the marketing version and the build.
    var versionText: String {
        let version = bundleInfo["CFBundleShortVersionString"] as? String ?? ""
        guard let build = bundleInfo["CFBundleVersion"] as? String, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }

    /// The flag `LaunchStateFlag` sets when the audio session can't start (#115), which makes every
    /// Siri intent answer "Audio temporarily unavailable" until playback starts again.
    var isAudioUnavailable: Bool { audioUnavailable() }

    static func formatted(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
