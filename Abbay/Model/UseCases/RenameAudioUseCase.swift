//
//  RenameAudioUseCase.swift
//  Abbay
//

import CoreData
import Foundation

protocol RenameAudioUseCaseProtocol {
    /// Saves the book's new name and returns the title it now shows: the name trimmed, or the
    /// file's name when that leaves nothing. Nil when there is no such book (it was deleted).
    @discardableResult
    func execute(title: String, bookURL url: URL) -> String?
}

/// Gives a book in the library another name (#322). A library change, so it also rewrites the App
/// Group snapshot Siri and CarPlay read (#85). An empty name is stored empty, so the book goes back
/// to being called by its file's name (`AudioModel.title(_:orFileTitleOf:)`).
final class RenameAudioUseCase: RenameAudioUseCaseProtocol {
    private let repository: LoadAudioRepositoryProtocol
    private let snapshotWriter: LibrarySnapshotWriterProtocol

    init(
        repository: LoadAudioRepositoryProtocol = LoadAudioRepository(),
        snapshotWriter: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter.shared
    ) {
        self.repository = repository
        self.snapshotWriter = snapshotWriter
    }

    @discardableResult
    func execute(title: String, bookURL url: URL) -> String? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = LocalStorage.persistent.performAndWait { _ -> Bool in
            guard let audio = repository.execute(url: url) else { return false }
            audio.setValue(name, forKey: #keyPath(AudioDataModel.title))
            LocalStorage.persistent.saveContext()
            return true
        }
        guard saved else { return nil }
        snapshotWriter.refresh()
        return AudioModel.title(name, orFileTitleOf: url)
    }
}
