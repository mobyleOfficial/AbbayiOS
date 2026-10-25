//
//  LoadAllAudiosUseCase.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/24.
//

import Foundation

final class LoadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol {
    private let repository: LoadAllAudiosRepositoryProtocol
    private let resolveBookmark: (Data?) -> ResolvedBookmark?
    private let staleBookmarks: StaleBookmarkSaver
    private let movedBooks: MovedBookKeyMigration

    init(
        repository: LoadAllAudiosRepositoryProtocol = LoadAllAudiosRepository(),
        resolveBookmark: @escaping (Data?) -> ResolvedBookmark? = URL.resolveBookmarkRefreshing,
        staleBookmarks: StaleBookmarkSaver = .shared,
        movedBooks: MovedBookKeyMigration = .shared
    ) {
        self.repository = repository
        self.resolveBookmark = resolveBookmark
        self.staleBookmarks = staleBookmarks
        self.movedBooks = movedBooks
    }

    /// Books whose bookmarks resolved as stale are saved with the fresh ones, in one call (#146).
    /// Moved books get their pre-#186 keys moved to their row (`MovedBookKeyMigration`).
    func execute() -> [AudioModel] {
        // Mapping faults the chapters relationship, so it runs on the context's queue too.
        let mapped = LocalStorage.persistent.performAndWait { _ in
            (repository.execute() ?? []).map { $0.mapped(resolveBookmark: resolveBookmark) }
        }
        staleBookmarks.save(mapped.compactMap(\.refreshedBookmark))
        let books = mapped.map(\.model)
        movedBooks.migrate(books)
        return books
    }
}
