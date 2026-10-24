//
//  LibrarySnapshotWriter.swift
//  Abbay
//

import Foundation
import os.log

private let snapshotLog = OSLog(subsystem: "com.edyuto.Abbay", category: "LibrarySnapshot")

struct LibrarySnapshotEntry: Codable, Equatable {
    let title: String
    let urlString: String
    let bookmarkData: Data?
}

struct LibrarySnapshot: Codable, Equatable {
    let version: Int
    let updatedAt: Date
    let audios: [LibrarySnapshotEntry]
}

extension Notification.Name {
    /// Posted after every library snapshot write, which every library mutation funnels through
    /// (import, delete, LibriVox additions, bookmark refreshes). Carries no payload: observers
    /// re-read the store. CarPlay rebuilds its list off this (#95).
    static let libraryDidChange = Notification.Name("abbay.libraryDidChange")
}

protocol LibrarySnapshotWriterProtocol {
    func write(audios: [AudioModel])
    func refresh()
}

/// Stub loader used as the extension-target default for `LibrarySnapshotWriter.init`.
/// The extension never calls `refresh()` (it only reads via `LibrarySnapshotReader`),
/// but the type system requires a concrete default. Returns empty.
private final class NoopLoadAllAudios: LoadAllAudiosUseCaseProtocol {
    func execute() -> [AudioModel] { [] }
}

final class LibrarySnapshotWriter: LibrarySnapshotWriterProtocol {
    static let key: String = "abbay.librarySnapshot.v1"

    static var shared: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter()

    private let store: KeyValueStoring
    private let loadAllAudios: LoadAllAudiosUseCaseProtocol

    #if ABBAY_INTENTS_EXTENSION
    init(store: KeyValueStoring = AppGroup.store, loadAllAudios: LoadAllAudiosUseCaseProtocol = NoopLoadAllAudios()) {
        self.store = store
        self.loadAllAudios = loadAllAudios
    }
    #else
    init(store: KeyValueStoring = AppGroup.store, loadAllAudios: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase()) {
        self.store = store
        self.loadAllAudios = loadAllAudios
    }
    #endif

    func write(audios: [AudioModel]) {
        let entries = audios.map { audio in
            LibrarySnapshotEntry(
                title: audio.title,
                urlString: audio.url?.absoluteString ?? "",
                bookmarkData: (audio.bookmarkData?.isEmpty == false) ? audio.bookmarkData : nil
            )
        }
        let snapshot = LibrarySnapshot(version: 1, updatedAt: Date(), audios: entries)
        if let data = try? JSONEncoder().encode(snapshot) {
            store.set(data, forKey: Self.key)
            let bookmarkCount = entries.filter { $0.bookmarkData != nil }.count
            os_log(
                "snapshot WRITTEN: %{public}d entries (%{public}d with bookmark), suite=%{public}@",
                log: snapshotLog,
                type: .info,
                entries.count,
                bookmarkCount,
                AppGroup.suiteName
            )
        } else {
            os_log("snapshot WRITE FAILED: JSON encode error", log: snapshotLog, type: .error)
        }

        #if !ABBAY_INTENTS_EXTENSION
        // Every library mutation funnels through here, so this is the one place that
        // keeps Siri's vocabulary, entity phrases and media-affinity signal in step
        // with the real library. None of those APIs exist in an app extension,
        // hence the guard.
        SiriLibraryPublisher.shared.publish(audios: audios)
        NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        #endif
    }

    func refresh() {
        write(audios: loadAllAudios.execute())
    }
}
