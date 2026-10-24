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
    private let forgetSettings: (URL?) -> Void

    /// - Parameter removeDownloads: Cancels a LibriVox book's downloads and deletes its files,
    ///   given its librivoxID. Defaults to the container's download manager, when configured.
    /// - Parameter forgetSettings: Drops the book's own settings (its speed). Defaults to the
    ///   container's settings, on the main thread, when configured.
    init(
        repository: DeleteAudioRepositoryProtocol = DeleteAudioRepository(),
        removeDownloads: @escaping (String) -> Void = { id in
            guard DependencyContainer.isConfigured else { return }
            DependencyContainer.shared.downloads.remove(bookID: id)
        },
        forgetSettings: @escaping (URL?) -> Void = DeleteAudioUseCase.forgetSettingsOnMain
    ) {
        self.repository = repository
        self.removeDownloads = removeDownloads
        self.forgetSettings = forgetSettings
    }

    func execute(_ audio: AudioModel) {
        if let id = audio.librivoxID {
            removeDownloads(id)
        }
        forgetSettings(audio.url)
        repository.execute(url: audio.url)
    }

    private static func forgetSettingsOnMain(_ url: URL?) {
        let forget = {
            // Checked when it runs: tests reset the container between cases.
            guard DependencyContainer.isConfigured else { return }
            DependencyContainer.shared.settings.forgetSpeed(for: url)
        }
        if Thread.isMainThread {
            forget()
        } else {
            DispatchQueue.main.async(execute: forget)
        }
    }
}
