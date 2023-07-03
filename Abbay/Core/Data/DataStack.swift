//
//  DataStack.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 03/07/23.
//

import CoreData

final class DataStack: ObservableObject {
    // MARK: - Properties
    private let modelName: String

    private lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: modelName)
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        return container
    }()

    lazy var managedContext: NSManagedObjectContext = persistentContainer.viewContext

    // MARK: - Init
    init(modelName: String) {
        self.modelName = modelName
    }

    // MARK: - Methods
    func saveContext() {
        guard managedContext.hasChanges else { return }
        do {
            try managedContext.save()
        } catch let error as NSError {
            print("Unresolved error \(error), \(error.userInfo)")
        }
    }
}

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

extension AudioDataModel {
    var model: AudioModel {
        var model = AudioModel()
        model.title = title ?? String()
        model.albumName = albumName ?? String()
        model.artist = artist ?? String()
        model.duration = duration
        model.currentTime = currentTime
        model.imageData = imageData
        model.url = url
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

extension ChapterModel {
    var dataModel: ChapterDataModel {
        let model = ChapterDataModel(context: LocalStorage.persistent.managedContext)
        model.setValue(title, forKey: #keyPath(ChapterDataModel.title))
        model.setValue(startTime, forKey: #keyPath(ChapterDataModel.startTime))
        model.setValue(duration, forKey: #keyPath(ChapterDataModel.duration))
        return model
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
