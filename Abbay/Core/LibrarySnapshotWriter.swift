//
//  LibrarySnapshotWriter.swift
//  Abbay
//

import Foundation
import os

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
    /// (`SaveAudioUseCase`, `DeleteAudioUseCase`, the player's bookmark refresh, launch). Carries no payload: observers
    /// re-read the store. CarPlay rebuilds its list off this (#95).
    static let libraryDidChange = Notification.Name("abbay.libraryDidChange")
}

/// What `LibrarySnapshotWriter` reports to `Log.librarySnapshot`. `siri-library-publish.md` tells
/// the reader to look for `snapshot WRITTEN` in `log stream` and sysdiagnoses, so the text is a
/// pure `record`, pinned by `LibrarySnapshotLogRecordTests` (#197). Counts and the App Group suite
/// name only, never a title.
enum LibrarySnapshotLogEvent: Equatable {
    case written(entryCount: Int, bookmarkCount: Int, suiteName: String)
    case encodeFailed

    var record: SiriLogRecord {
        switch self {
        case let .written(entryCount, bookmarkCount, suiteName):
            SiriLogRecord(
                level: .info,
                message: "snapshot WRITTEN: \(entryCount) entries (\(bookmarkCount) with bookmark), suite=\(suiteName)",
                privacy: .public
            )
        case .encodeFailed:
            SiriLogRecord(level: .error, message: "snapshot WRITE FAILED: JSON encode error", privacy: .public)
        }
    }

    /// The production sink: `Log.librarySnapshot`.
    static func writeToLog(_ event: LibrarySnapshotLogEvent) {
        Log.librarySnapshot.write(event.record)
    }
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

    static let shared: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter()

    private let store: KeyValueStoring
    private let loadAllAudios: LoadAllAudiosUseCaseProtocol
    /// Injected so tests see what was logged without reading the unified log (#181, #197).
    private let log: (LibrarySnapshotLogEvent) -> Void

    #if ABBAY_INTENTS_EXTENSION
    init(
        store: KeyValueStoring = AppGroup.store,
        loadAllAudios: LoadAllAudiosUseCaseProtocol = NoopLoadAllAudios(),
        log: @escaping (LibrarySnapshotLogEvent) -> Void = LibrarySnapshotLogEvent.writeToLog
    ) {
        self.store = store
        self.loadAllAudios = loadAllAudios
        self.log = log
    }
    #else
    private let publisher: SiriLibraryPublisherProtocol

    init(
        store: KeyValueStoring = AppGroup.store,
        loadAllAudios: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase(),
        publisher: SiriLibraryPublisherProtocol = SiriLibraryPublisher.shared,
        log: @escaping (LibrarySnapshotLogEvent) -> Void = LibrarySnapshotLogEvent.writeToLog
    ) {
        self.store = store
        self.loadAllAudios = loadAllAudios
        self.publisher = publisher
        self.log = log
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
            log(.written(entryCount: entries.count, bookmarkCount: bookmarkCount, suiteName: AppGroup.suiteName))
        } else {
            log(.encodeFailed)
        }

        #if !ABBAY_INTENTS_EXTENSION
        // Every library mutation funnels through here, so this is the one place that
        // keeps Siri's vocabulary, entity phrases and media-affinity signal in step
        // with the real library. None of those APIs exist in an app extension,
        // hence the guard.
        publisher.publish(audios: audios)
        NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        #endif
    }

    func refresh() {
        write(audios: loadAllAudios.execute())
    }
}
