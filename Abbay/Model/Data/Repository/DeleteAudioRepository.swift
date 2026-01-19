//
//  DeleteAudioRepository.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 18/01/26.
//

import CoreData
import Foundation

protocol DeleteAudioRepositoryProtocol {
    func execute(url: URL?)
}

final class DeleteAudioRepository: DeleteAudioRepositoryProtocol {
    private let loadAudioRepository: LoadAudioRepositoryProtocol

    init(loadAudioRepository: LoadAudioRepositoryProtocol = LoadAudioRepository()) {
        self.loadAudioRepository = loadAudioRepository
    }

    func execute(url: URL?) {
        guard let audioDataModel = loadAudioRepository.execute(url: url) else { return }

        let context = LocalStorage.persistent.managedContext
        context.delete(audioDataModel)
        LocalStorage.persistent.saveContext()
    }
}
