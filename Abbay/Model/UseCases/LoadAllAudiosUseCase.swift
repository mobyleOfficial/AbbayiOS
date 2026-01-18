//
//  LoadAllAudiosUseCase.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/24.
//

import CoreData
import Foundation

protocol LoadAllAudiosUseCaseProtocol {
    func execute() -> [AudioModel]
}

final class LoadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol {
    func execute() -> [AudioModel] {
        let request = AudioDataModel.fetchRequest()
        let sortByTitle = NSSortDescriptor(key: #keyPath(AudioDataModel.title), ascending: false)
        request.sortDescriptors = [sortByTitle]
        do {
            let context = LocalStorage.persistent.managedContext
            let result = try context.fetch(request)
            return result.compactMap { $0.model }
        } catch let error as NSError {
            print("Fetch error: \(error) description: \(error.userInfo)")
        }
        return [AudioModel]()
    }
}
