//
//  DataToModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 08/07/23.
//

import Foundation

extension AudioDataModel {
    var model: AudioModel {
        var model = AudioModel()
        model.title = title ?? String()
        model.albumName = albumName ?? String()
        model.artist = artist ?? String()
        model.duration = duration
        model.currentTime = currentTime
        model.imageData = imageData
        model.bookmarkData = bookmarkData

        // Try to resolve bookmark first, fallback to URL
        model.url = URL.resolveBookmark(from: bookmarkData) ?? url

        model.chapters = chapters?.compactMap({ ($0 as? ChapterDataModel)?.model }) ?? []
        return model
    }

    static func load(_ url: URL?) -> AudioDataModel? {
        guard let url = url else { return nil }
        let request = AudioDataModel.fetchRequest()
        let predicate = NSPredicate(format: "%K == %@", #keyPath(AudioDataModel.url), url as NSURL)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate])
        do {
            let context = LocalStorage.persistent.managedContext
            let result = try context.fetch(request)
            return result.first
        } catch let error as NSError {
            print("Fetch error: \(error) description: \(error.userInfo)")
        }
        return nil
    }

    static func load() -> [AudioDataModel] {
        let request = AudioDataModel.fetchRequest()
        let sortByTitle = NSSortDescriptor(key: #keyPath(AudioDataModel.title), ascending: false)
        request.sortDescriptors = [sortByTitle]
        do {
            let context = LocalStorage.persistent.managedContext
            let result = try context.fetch(request)
            return result
        } catch let error as NSError {
            print("Fetch error: \(error) description: \(error.userInfo)")
        }
        return [AudioDataModel]()
    }
}

extension ChapterDataModel {
    var model: ChapterModel {
        var model = ChapterModel()
        model.title = title ?? String()
        model.startTime = startTime
        model.duration = duration
        return model
    }
}
