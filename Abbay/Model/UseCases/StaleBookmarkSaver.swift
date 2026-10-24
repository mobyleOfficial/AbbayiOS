//
//  StaleBookmarkSaver.swift
//  Abbay
//

import Foundation
import os

/// Saves the fresh bookmark of a book whose stored one resolved as stale (#146), through the save
/// use case (one Core Data save and one snapshot write per call, #143).
///
/// Each book is saved at most once per launch. Saving refreshes the library snapshot, which loads
/// the library again; if iOS kept calling the new bookmark stale, saving on every load would loop.
final class StaleBookmarkSaver {
    static let shared = StaleBookmarkSaver()

    /// Made on first use: `SaveAudioUseCase` defaults to `LibrarySnapshotWriter.shared`, whose own
    /// default load use case holds this saver, so building it eagerly would be a cycle.
    private let makeSave: () -> SaveAudioUseCaseProtocol
    private lazy var save = makeSave()
    private var saved = Set<URL>()
    private let lock = NSLock()

    init(save: @escaping () -> SaveAudioUseCaseProtocol = { SaveAudioUseCase() }) {
        makeSave = save
    }

    /// `books` carry their row's URL and the fresh bookmark (`MappedAudio.refreshedBookmark`).
    func save(_ books: [AudioModel]) {
        let toSave: [AudioModel] = lock.withLock {
            let new = books.filter { book in
                guard let url = book.url else { return false }
                return saved.insert(url).inserted
            }
            return new
        }
        guard !toSave.isEmpty else { return }
        // Outside the lock: the save's snapshot refresh loads the library again, and lands here.
        do {
            try saveUseCase().execute(toSave)
            Log.bookmarks.info("saved \(toSave.count, privacy: .public) refreshed bookmark(s)")
        } catch {
            let error = error as NSError
            Log.bookmarks.error(
                "saving refreshed bookmarks failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)"
            )
        }
    }

    private func saveUseCase() -> SaveAudioUseCaseProtocol {
        lock.withLock { save }
    }
}
