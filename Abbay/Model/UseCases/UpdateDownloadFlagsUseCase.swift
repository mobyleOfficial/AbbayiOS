//
//  UpdateDownloadFlagsUseCase.swift
//  Abbay
//

import Foundation

protocol UpdateDownloadFlagsUseCaseProtocol {
    /// Writes only the flags that are non-nil, on the book already saved under `url`.
    /// Does nothing when no book has that url.
    func execute(url: URL?, isDownloadPaused: Bool?, allowsCellularDownload: Bool?)
}

/// The only writer of a saved book's download flags. `SaveAudioUseCase` leaves them alone on
/// existing books, so a stale `AudioModel` (the player's cached copy) can't undo a pause.
final class UpdateDownloadFlagsUseCase: UpdateDownloadFlagsUseCaseProtocol {
    private let repository: LoadAudioRepositoryProtocol

    init(repository: LoadAudioRepositoryProtocol = LoadAudioRepository()) {
        self.repository = repository
    }

    func execute(url: URL?, isDownloadPaused: Bool?, allowsCellularDownload: Bool?) {
        guard let model = repository.execute(url: url) else { return }

        if let isDownloadPaused {
            model.setValue(isDownloadPaused, forKey: #keyPath(AudioDataModel.isDownloadPaused))
        }
        if let allowsCellularDownload {
            model.setValue(allowsCellularDownload, forKey: #keyPath(AudioDataModel.allowsCellularDownload))
        }

        LocalStorage.persistent.saveContext()
    }
}
