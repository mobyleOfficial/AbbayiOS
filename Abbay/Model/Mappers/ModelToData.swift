//
//  ModelToData.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 08/07/23.
//

import Foundation

extension AudioModel {
    var dataModel: AudioDataModel {
        let model: AudioDataModel
        var shouldSaveChapters = false
        if let loaded = AudioDataModel.load(url) {
            model = loaded
        } else {
            shouldSaveChapters = true
            model = AudioDataModel(context: LocalStorage.persistent.managedContext)
        }
        model.setValue(albumName, forKey: #keyPath(AudioDataModel.albumName))
        model.setValue(artist, forKey: #keyPath(AudioDataModel.artist))
        model.setValue(currentTime, forKey: #keyPath(AudioDataModel.currentTime))
        model.setValue(duration, forKey: #keyPath(AudioDataModel.duration))
        model.setValue(imageData, forKey: #keyPath(AudioDataModel.imageData))
        model.setValue(title, forKey: #keyPath(AudioDataModel.title))
        model.setValue(url, forKey: #keyPath(AudioDataModel.url))
        if shouldSaveChapters {
            for chapter in chapters {
                model.addToChapters(chapter.dataModel)
            }
        }
        return model
    }

    func save() {
        _ = dataModel
        try? LocalStorage.persistent.managedContext.save()
    }

    static func load(_ url: URL?) -> AudioModel? {
        AudioDataModel.load(url)?.model
    }

    static func load() -> [AudioModel] {
        AudioDataModel.load()
            .compactMap({ $0.model })
            .sorted(by: { $0.title.lowercased() < $1.title.lowercased() })
    }
}

extension ChapterModel {
    var dataModel: ChapterDataModel {
        let model = ChapterDataModel(context: LocalStorage.persistent.managedContext)
        model.setValue(title, forKey: #keyPath(ChapterDataModel.title))
        model.setValue(startTime, forKey: #keyPath(ChapterDataModel.startTime))
        model.setValue(duration, forKey: #keyPath(ChapterDataModel.duration))
        return model
    }
}
