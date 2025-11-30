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
