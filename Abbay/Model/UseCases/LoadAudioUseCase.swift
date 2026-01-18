//
//  LoadAudioUseCase.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/24.
//

import CoreData
import Foundation

protocol LoadAudioUseCaseProtocol {
    func execute(url: URL?) -> AudioModel?
}

final class LoadAudioUseCase: LoadAudioUseCaseProtocol {
    private let repository: LoadAudioRepositoryProtocol

    init(repository: LoadAudioRepositoryProtocol) {
        self.repository = repository
    }

    func execute(url: URL?) -> AudioModel? {
        guard let url = url else { return nil }
        let dataModel = repository.execute(url: url)
        return dataModel?.model
    }
}
