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
    private let resolveBookmark: (Data?) -> ResolvedBookmark?
    private let staleBookmarks: StaleBookmarkSaver
    private let movedBooks: MovedBookKeyMigration

    init(
        repository: LoadAudioRepositoryProtocol = LoadAudioRepository(),
        resolveBookmark: @escaping (Data?) -> ResolvedBookmark? = URL.resolveBookmarkRefreshing,
        staleBookmarks: StaleBookmarkSaver = .shared,
        movedBooks: MovedBookKeyMigration = .shared
    ) {
        self.repository = repository
        self.resolveBookmark = resolveBookmark
        self.staleBookmarks = staleBookmarks
        self.movedBooks = movedBooks
    }

    /// A book whose bookmark resolved as stale is saved with the fresh one (#146); a moved book gets
    /// its pre-#186 keys moved to its row (`MovedBookKeyMigration`).
    func execute(url: URL?) -> AudioModel? {
        guard let url = url else { return nil }
        let mapped = LocalStorage.persistent.performAndWait { _ in
            repository.execute(url: url)?.mapped(resolveBookmark: resolveBookmark)
        }
        if let refreshed = mapped?.refreshedBookmark {
            staleBookmarks.save([refreshed])
        }
        if let model = mapped?.model {
            movedBooks.migrate([model])
        }
        return mapped?.model
    }
}
