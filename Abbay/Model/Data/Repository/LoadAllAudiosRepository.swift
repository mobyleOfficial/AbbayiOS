//
//  LoadAllAudiosRepository.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 18/01/26.
//

import CoreData
import Foundation
import os

/// Returns managed objects of `LocalStorage.persistent`'s context: read them only inside its
/// `performAndWait`.
protocol LoadAllAudiosRepositoryProtocol {
    func execute() -> [AudioDataModel]?
}

final class LoadAllAudiosRepository: LoadAllAudiosRepositoryProtocol {
    func execute() -> [AudioDataModel]? {
        let request = AudioDataModel.fetchRequest()
        let sortByTitle = NSSortDescriptor(key: #keyPath(AudioDataModel.title), ascending: false)
        request.sortDescriptors = [sortByTitle]
        return LocalStorage.persistent.performAndWait { context in
            do {
                return try context.fetch(request)
            } catch let error as NSError {
                Log.data.error("fetch all failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            }
            return [AudioDataModel]()
        }
    }
}
