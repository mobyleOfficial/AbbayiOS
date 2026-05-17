//
//  LibrarySnapshotWriter.swift
//  Abbay
//

import Foundation

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

final class LibrarySnapshotWriter: LibrarySnapshotWriterProtocol {
    static let key: String = "abbay.librarySnapshot.v1"

    static var defaults: UserDefaults = AppGroup.defaults
    static var shared: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter()

    private let loadAllAudios: LoadAllAudiosUseCaseProtocol

    init(loadAllAudios: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase()) {
        self.loadAllAudios = loadAllAudios
    }

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
        }
    }

    func refresh() {
        write(audios: loadAllAudios.execute())
    }
}
