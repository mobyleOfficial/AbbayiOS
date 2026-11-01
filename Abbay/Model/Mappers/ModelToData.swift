//
//  ModelToData.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 08/07/23.
//

import CoreData
import Foundation

extension ChapterModel {
    /// Inserts a new chapter into `context`. Call on `context`'s queue.
    func dataModel(in context: NSManagedObjectContext) -> ChapterDataModel {
        let model = ChapterDataModel(context: context)
        model.setValue(title, forKey: #keyPath(ChapterDataModel.title))
        model.setValue(startTime, forKey: #keyPath(ChapterDataModel.startTime))
        model.setValue(duration, forKey: #keyPath(ChapterDataModel.duration))
        model.setValue(remoteURL, forKey: #keyPath(ChapterDataModel.remoteURL))
        model.setValue(expectedBytes, forKey: #keyPath(ChapterDataModel.expectedBytes))
        model.setValue(resumeOffset.map(NSNumber.init(value:)), forKey: #keyPath(ChapterDataModel.resumeOffset))
        return model
    }
}
