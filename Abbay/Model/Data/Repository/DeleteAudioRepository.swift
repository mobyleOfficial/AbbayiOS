//
//  DeleteAudioRepository.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 18/01/26.
//

import CoreData
import Foundation

protocol DeleteAudioRepositoryProtocol {
    /// Deletes the row stored under `url`: pass the book's `rowURL`, not the URL it plays from.
    func execute(url: URL?)
}

final class DeleteAudioRepository: DeleteAudioRepositoryProtocol {
    private let loadAudioRepository: LoadAudioRepositoryProtocol

    init(loadAudioRepository: LoadAudioRepositoryProtocol = LoadAudioRepository()) {
        self.loadAudioRepository = loadAudioRepository
    }

    func execute(url: URL?) {
        LocalStorage.persistent.performAndWait { context in
            guard let audioDataModel = loadAudioRepository.execute(url: url) else { return }

            context.delete(audioDataModel)
            LocalStorage.persistent.saveContext()
        }
    }
}
