//
//  LoadAudioRepository.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 18/01/26.
//

import CoreData
import Foundation

protocol LoadAudioRepositoryProtocol {
    func execute(url: URL?) -> AudioDataModel?
}

final class LoadAudioRepository: LoadAudioRepositoryProtocol {
    func execute(url: URL?) -> AudioDataModel? {
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
}
