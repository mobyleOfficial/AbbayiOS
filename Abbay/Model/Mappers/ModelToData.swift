//
//  ModelToData.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 08/07/23.
//

import Foundation

extension ChapterModel {
    var dataModel: ChapterDataModel {
        let model = ChapterDataModel(context: LocalStorage.persistent.managedContext)
        model.setValue(title, forKey: #keyPath(ChapterDataModel.title))
        model.setValue(startTime, forKey: #keyPath(ChapterDataModel.startTime))
        model.setValue(duration, forKey: #keyPath(ChapterDataModel.duration))
        return model
    }
}
