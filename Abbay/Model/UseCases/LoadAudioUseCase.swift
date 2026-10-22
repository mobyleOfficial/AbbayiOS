//
//  LoadAudioUseCase.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/24.
//

import Foundation

protocol LoadAudioUseCaseProtocol {
    func execute(url: URL?) -> AudioModel?
}

final class LoadAudioUseCase: LoadAudioUseCaseProtocol {
    private let repository: LoadAudioRepositoryProtocol

    init(repository: LoadAudioRepositoryProtocol = LoadAudioRepository()) {
        self.repository = repository
    }

    func execute(url: URL?) -> AudioModel? {
        guard let url = url else { return nil }
        return LocalStorage.persistent.performAndWait { _ in
            repository.execute(url: url)?.model
        }
    }
}
