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
    private let removeDownloads: (String) -> Void

    /// - Parameter removeDownloads: Cancels a LibriVox book's downloads and deletes its files,
    ///   given its librivoxID. Defaults to the container's download manager, when configured.
    init(
        repository: DeleteAudioRepositoryProtocol = DeleteAudioRepository(),
        removeDownloads: @escaping (String) -> Void = { id in
            guard DependencyContainer.isConfigured else { return }
            DependencyContainer.shared.downloads.remove(bookID: id)
        }
    ) {
        self.repository = repository
        self.removeDownloads = removeDownloads
    }

    func execute(_ audio: AudioModel) {
        if let id = audio.librivoxID {
            removeDownloads(id)
        }
        repository.execute(url: audio.url)
    }
}
