//
//  DeleteAudioUseCase.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 18/01/26.
//

import Foundation

protocol DeleteAudioUseCaseProtocol {
    func execute(_ audio: AudioModel)
}

final class DeleteAudioUseCase: DeleteAudioUseCaseProtocol {
    private let repository: DeleteAudioRepositoryProtocol

    init(repository: DeleteAudioRepositoryProtocol = DeleteAudioRepository()) {
        self.repository = repository
    }

    func execute(_ audio: AudioModel) {
        repository.execute(url: audio.url)
    }
}
