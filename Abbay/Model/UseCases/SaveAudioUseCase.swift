//
//  SaveAudioUseCase.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/24.
//

import CoreData
import Foundation

protocol SaveAudioUseCaseProtocol {
    /// Saves the books in one go: one Core Data save, one library snapshot write.
    func execute(_ audios: [AudioModel]) throws
}

extension SaveAudioUseCaseProtocol {
    func execute(_ audio: AudioModel) throws {
        try execute([audio])
    }
}

/// Adds books to the library (an import, a LibriVox book). Saving is a library change, so it also
/// rewrites the App Group snapshot Siri and CarPlay read: callers can't forget to (#85).
final class SaveAudioUseCase: SaveAudioUseCaseProtocol {
    private let repository: LoadAudioRepositoryProtocol
    private let snapshotWriter: LibrarySnapshotWriterProtocol

    init(
        repository: LoadAudioRepositoryProtocol = LoadAudioRepository(),
        snapshotWriter: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter.shared
    ) {
        self.repository = repository
        self.snapshotWriter = snapshotWriter
    }

    func execute(_ audios: [AudioModel]) throws {
        guard !audios.isEmpty else { return }
        LocalStorage.persistent.performAndWait { context in
            for audio in audios {
                // By the row's key, so a loaded book whose file moved updates its own row instead
                // of inserting a second one under the resolved URL (#176).
                let existingAudio = repository.execute(url: audio.rowURL)

                updateAudio(existingAudio, with: audio, in: context)
            }

            LocalStorage.persistent.saveContext()
        }
        snapshotWriter.refresh()
    }

    /// Call on `context`'s queue.
    private func updateAudio(
        _ existing: AudioDataModel?,
        with new: AudioModel,
        in context: NSManagedObjectContext
    ) {
        let model = existing ?? AudioDataModel(context: context)

        model.setValue(new.albumName, forKey: #keyPath(AudioDataModel.albumName))
        model.setValue(new.artist, forKey: #keyPath(AudioDataModel.artist))
        model.setValue(new.currentTime, forKey: #keyPath(AudioDataModel.currentTime))
        model.setValue(new.duration, forKey: #keyPath(AudioDataModel.duration))
        model.setValue(new.imageData, forKey: #keyPath(AudioDataModel.imageData))
        model.setValue(new.title, forKey: #keyPath(AudioDataModel.title))
        // The key stays the stored URL: `LastPlayedStore`, the Siri snapshot and per-book speeds
        // are keyed by it too.
        model.setValue(new.rowURL, forKey: #keyPath(AudioDataModel.url))
        model.setValue(new.librivoxID, forKey: #keyPath(AudioDataModel.librivoxID))
        model.setValue(new.totalBytes, forKey: #keyPath(AudioDataModel.totalBytes))

        if let bookmarkData = new.bookmarkData ?? existing?.bookmarkData {
            model.setValue(bookmarkData, forKey: #keyPath(AudioDataModel.bookmarkData))
        }

        // Download flags are written once, on insert. Afterwards only `UpdateDownloadFlagsUseCase`
        // changes them, so saving a stale model (the player's cached copy) can't undo a pause.
        if existing == nil {
            model.setValue(new.allowsCellularDownload, forKey: #keyPath(AudioDataModel.allowsCellularDownload))
            model.setValue(new.isDownloadPaused, forKey: #keyPath(AudioDataModel.isDownloadPaused))
            for chapter in new.chapters {
                model.addToChapters(chapter.dataModel(in: context))
            }
        }
    }
}
