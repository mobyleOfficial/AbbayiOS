//
//  SaveAudioUseCase.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/24.
//

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
        let existingAudio = repository.execute(url: audio.url)

        updateAudio(existingAudio, with: audio)

        LocalStorage.persistent.saveContext()
    }

    private func updateAudio(
        _ existing: AudioDataModel?,
        with new: AudioModel
    ) {
        let model = existing ?? AudioDataModel(context: LocalStorage.persistent.managedContext)

        model.setValue(new.albumName, forKey: #keyPath(AudioDataModel.albumName))
        model.setValue(new.artist, forKey: #keyPath(AudioDataModel.artist))
        model.setValue(new.currentTime, forKey: #keyPath(AudioDataModel.currentTime))
        model.setValue(new.duration, forKey: #keyPath(AudioDataModel.duration))
        model.setValue(new.imageData, forKey: #keyPath(AudioDataModel.imageData))
        model.setValue(new.title, forKey: #keyPath(AudioDataModel.title))
        model.setValue(new.url, forKey: #keyPath(AudioDataModel.url))

        if let bookmarkData = new.bookmarkData ?? existing?.bookmarkData {
            model.setValue(bookmarkData, forKey: #keyPath(AudioDataModel.bookmarkData))
        }

        if existing == nil {
            for chapter in new.chapters {
                model.addToChapters(chapter.dataModel)
            }
        }
    }
}
