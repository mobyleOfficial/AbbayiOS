//
//  LoadChapterResumeUseCase.swift
//  Abbay
//

import Foundation

protocol LoadChapterResumeUseCaseProtocol {
    /// Where playing chapter `index` of `book` starts (#299), from the saved book rather than the
    /// copy passed in: a screen's or the player's copy can predate the last save of that chapter.
    /// A book not saved falls back to the copy's chapter.
    func resumeTime(ofChapter index: Int, in book: AudioModel) -> Double?
}

final class LoadChapterResumeUseCase: LoadChapterResumeUseCaseProtocol {
    private let repository: LoadAudioRepositoryProtocol

    init(repository: LoadAudioRepositoryProtocol = LoadAudioRepository()) {
        self.repository = repository
    }

    func resumeTime(ofChapter index: Int, in book: AudioModel) -> Double? {
        guard book.chapters.indices.contains(index) else { return nil }
        let saved: ChapterModel? = LocalStorage.persistent.performAndWait { _ in
            guard let chapters = repository.execute(url: book.url)?.chapters,
                  chapters.count == book.chapters.count else { return nil }
            return (chapters[index] as? ChapterDataModel)?.model
        }
        return (saved ?? book.chapters[index]).resumeTime
    }
}
