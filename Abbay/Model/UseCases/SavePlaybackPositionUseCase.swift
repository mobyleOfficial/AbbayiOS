//
//  SavePlaybackPositionUseCase.swift
//  Abbay
//

import Foundation

protocol SavePlaybackPositionUseCaseProtocol {
    /// Writes `currentTime`, and `bookmarkData` when non-nil, on the book already saved under `url`.
    /// Does nothing when no book has that url.
    func execute(url: URL?, currentTime: Double, bookmarkData: Data?)
}

/// The player's only writer. Unlike `SaveAudioUseCase` it never inserts, so a book deleted while
/// the player still holds it stays deleted (a re-inserted LibriVox row would re-download on launch).
final class SavePlaybackPositionUseCase: SavePlaybackPositionUseCaseProtocol {
    private let repository: LoadAudioRepositoryProtocol

    init(repository: LoadAudioRepositoryProtocol = LoadAudioRepository()) {
        self.repository = repository
    }

    func execute(url: URL?, currentTime: Double, bookmarkData: Data?) {
        guard let model = repository.execute(url: url) else { return }

        model.setValue(currentTime, forKey: #keyPath(AudioDataModel.currentTime))
        if let bookmarkData {
            model.setValue(bookmarkData, forKey: #keyPath(AudioDataModel.bookmarkData))
        }

        LocalStorage.persistent.saveContext()
    }
}
