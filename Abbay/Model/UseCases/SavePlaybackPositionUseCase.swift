//
//  SavePlaybackPositionUseCase.swift
//  Abbay
//

import Foundation

protocol SavePlaybackPositionUseCaseProtocol {
    /// Writes `currentTime`, `bookmarkData` when non-nil and `chapter`'s offset when non-nil, on the
    /// book already saved under `url` (the book's `url`, not its `fileURL`). Does nothing when no
    /// book has that url.
    func execute(url: URL?, currentTime: Double, bookmarkData: Data?, chapter: ChapterPosition?)
}

extension SavePlaybackPositionUseCaseProtocol {
    func execute(url: URL?, currentTime: Double, bookmarkData: Data?) {
        execute(url: url, currentTime: currentTime, bookmarkData: bookmarkData, chapter: nil)
    }
}

/// The player's only writer. Unlike `SaveAudioUseCase` it never inserts, so a book deleted while
/// the player still holds it stays deleted (a re-inserted LibriVox row would re-download on launch).
final class SavePlaybackPositionUseCase: SavePlaybackPositionUseCaseProtocol {
    private let repository: LoadAudioRepositoryProtocol

    init(repository: LoadAudioRepositoryProtocol = LoadAudioRepository()) {
        self.repository = repository
    }

    func execute(url: URL?, currentTime: Double, bookmarkData: Data?, chapter: ChapterPosition?) {
        var saved = false
        LocalStorage.persistent.performAndWait { _ in
            guard let model = repository.execute(url: url) else { return }

            model.setValue(currentTime, forKey: #keyPath(AudioDataModel.currentTime))
            if let bookmarkData {
                model.setValue(bookmarkData, forKey: #keyPath(AudioDataModel.bookmarkData))
            }
            if let chapter, let chapters = model.chapters, chapters.count > chapter.index, chapter.index >= 0,
               let row = chapters[chapter.index] as? ChapterDataModel {
                row.setValue(NSNumber(value: chapter.offset), forKey: #keyPath(ChapterDataModel.resumeOffset))
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
