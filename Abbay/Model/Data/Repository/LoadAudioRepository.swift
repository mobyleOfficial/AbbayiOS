//
//  LoadAudioRepository.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 18/01/26.
//

import CoreData
import Foundation
import os

/// Returns a managed object of `LocalStorage.persistent`'s context: read or change it only inside
/// its `performAndWait`.
protocol LoadAudioRepositoryProtocol {
    func execute(url: URL?) -> AudioDataModel?
}

final class LoadAudioRepository: LoadAudioRepositoryProtocol {
    func execute(url: URL?) -> AudioDataModel? {
        guard let url = url else { return nil }
        let request = AudioDataModel.fetchRequest()
        let predicate = NSPredicate(format: "%K == %@", #keyPath(AudioDataModel.url), url as NSURL)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate])
        return LocalStorage.persistent.performAndWait { context in
            do {
                return try context.fetch(request).first
            } catch let error as NSError {
                // Logged, not reported: a fetch runs on every row and tick, and the save that
                // could lose data already reports its own failure.
                Log.data.error("fetch one failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            }
            return nil
        }
    }
}
