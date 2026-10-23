//
//  SaveAudioUseCase.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/24.
//

import CoreData
import Foundation

protocol SaveAudioUseCaseProtocol {
    func execute(_ audio: AudioModel) throws
}

final class SaveAudioUseCase: SaveAudioUseCaseProtocol {
    private let repository: LoadAudioRepositoryProtocol

    init(repository: LoadAudioRepositoryProtocol = LoadAudioRepository()) {
        self.repository = repository
    }

    func execute(_ audio: AudioModel) throws {
        LocalStorage.persistent.performAndWait { context in
            let existingAudio = repository.execute(url: audio.url)

            updateAudio(existingAudio, with: audio, in: context)

            LocalStorage.persistent.saveContext()
        }
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
        model.setValue(new.url, forKey: #keyPath(AudioDataModel.url))
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
