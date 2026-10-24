//
//  SavePlaybackPositionUseCase.swift
//  Abbay
//

import Foundation

protocol SavePlaybackPositionUseCaseProtocol {
    /// Writes `currentTime`, and `bookmarkData` when non-nil, on the book already saved under `url`
    /// (the book's `rowURL`). Does nothing when no book has that url.
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
        var saved = false
        LocalStorage.persistent.performAndWait { _ in
            guard let model = repository.execute(url: url) else { return }

            model.setValue(currentTime, forKey: #keyPath(AudioDataModel.currentTime))
            if let bookmarkData {
                model.setValue(bookmarkData, forKey: #keyPath(AudioDataModel.bookmarkData))
            }

            LocalStorage.persistent.saveContext()
            saved = true
        }
        if saved, let url {
            NotificationCenter.default.post(
                name: .playbackPositionDidSave,
                object: nil,
                userInfo: [PlaybackPositionSave.urlKey: url]
            )
        }
    }
}

extension Notification.Name {
    /// Posted after a book's position is written: every 10 s while playing, and on pause, a book
    /// switch, a chapter jump or backgrounding. Not a library change (no snapshot write), so it
    /// has its own signal: CarPlay refreshes that book's row off it (#150). Posted on the saving
    /// thread; `userInfo[PlaybackPositionSave.urlKey]` is the book's URL.
    static let playbackPositionDidSave = Notification.Name("abbay.playbackPositionDidSave")
}

enum PlaybackPositionSave {
    static let urlKey = "url"
}
