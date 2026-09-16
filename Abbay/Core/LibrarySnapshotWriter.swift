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

    static var defaults: UserDefaults = AppGroup.defaults
    static var shared: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter()

    private let loadAllAudios: LoadAllAudiosUseCaseProtocol

    #if ABBAY_INTENTS_EXTENSION
    init(loadAllAudios: LoadAllAudiosUseCaseProtocol = NoopLoadAllAudios()) {
        self.loadAllAudios = loadAllAudios
    }
    #else
    init(loadAllAudios: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase()) {
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
            Self.defaults.set(data, forKey: Self.key)
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
        #endif
    }

    func refresh() {
        write(audios: loadAllAudios.execute())
    }
}
