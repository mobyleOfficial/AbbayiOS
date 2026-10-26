//
//  LibrarySnapshotReader.swift
//  Abbay
//

import Foundation

/// Reads the library snapshot `LibrarySnapshotWriter` keeps in the App Group store. The store is
/// injected; production uses `shared`.
struct LibrarySnapshotReader {
    static let shared = LibrarySnapshotReader()

    private let store: KeyValueStoring

    init(store: KeyValueStoring = AppGroup.store) {
        self.store = store
    }

    func read() -> [LibrarySnapshotEntry] {
        guard let data = store.object(forKey: LibrarySnapshotWriter.key) as? Data,
              let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) else {
            return []
        }
        return snapshot.audios
    }
}
