//
//  LoadAllAudiosRepository.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 18/01/26.
//

import CoreData
import Foundation

protocol LoadAllAudiosRepositoryProtocol {
    func execute() -> [AudioDataModel]?
}

final class LoadAllAudiosRepository: LoadAllAudiosRepositoryProtocol {
    func execute() -> [AudioDataModel]? {
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
