//
//  LibrarySnapshotReader.swift
//  Abbay
//

import Foundation

enum LibrarySnapshotReader {
    static var defaults: UserDefaults = AppGroup.defaults

    static func read() -> [LibrarySnapshotEntry] {
        guard let data = defaults.data(forKey: LibrarySnapshotWriter.key),
              let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) else {
            return []
        }
        return snapshot.audios
    }
}
