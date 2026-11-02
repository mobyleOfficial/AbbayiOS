//
//  SaveChaptersUseCase.swift
//  Abbay
//

import CoreData
import Foundation

protocol SaveChaptersUseCaseProtocol {
    /// Replaces the chapters of the book saved under `url`, and returns them as saved: a chapter
    /// that starts where a saved one did keeps that one's resume offset (#299), so a list that grows
    /// while it is listened to doesn't forget where the listener is. Nil when there is no such book
    /// (it was deleted meanwhile), and then nothing is written.
    @discardableResult
    func execute(_ chapters: [ChapterModel], bookURL url: URL) -> [ChapterModel]?
}

/// Gives a book in the library new chapters, or none: the chapters a search of its audio found
/// (`ChapterFinder`), or taking them away again. `SaveAudioUseCase` writes chapters only when a book
/// is first added, so this is the one way to change them later. A library change, so it also
/// rewrites the App Group snapshot Siri and CarPlay read (#85).
final class SaveChaptersUseCase: SaveChaptersUseCaseProtocol {
    private let repository: LoadAudioRepositoryProtocol
    private let snapshotWriter: LibrarySnapshotWriterProtocol

    init(
        repository: LoadAudioRepositoryProtocol = LoadAudioRepository(),
        snapshotWriter: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter.shared
    ) {
        self.repository = repository
        self.snapshotWriter = snapshotWriter
    }

    /// How close two chapter starts must be to be the same chapter.
    static let sameStartTolerance = 0.5

    @discardableResult
    func execute(_ chapters: [ChapterModel], bookURL url: URL) -> [ChapterModel]? {
        let saved = LocalStorage.persistent.performAndWait { context -> [ChapterModel]? in
            guard let audio = repository.execute(url: url) else { return nil }
            let old = (audio.chapters?.array ?? []).compactMap { $0 as? ChapterDataModel }
            let merged = chapters.map { chapter in
                var chapter = chapter
                if chapter.resumeOffset == nil,
                   let same = old.first(where: { abs($0.startTime - chapter.startTime) <= Self.sameStartTolerance }) {
                    chapter.resumeOffset = same.resumeOffset?.doubleValue
                }
                return chapter
            }
            // The relationship nullifies: the old rows are deleted, not left orphaned.
            for row in old {
                context.delete(row)
            }
            audio.chapters = NSOrderedSet(array: merged.map { $0.dataModel(in: context) })
            LocalStorage.persistent.saveContext()
            return merged
        }
        if saved != nil {
            snapshotWriter.refresh()
        }
        return saved
    }
}
