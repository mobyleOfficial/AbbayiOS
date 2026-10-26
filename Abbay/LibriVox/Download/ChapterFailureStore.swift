//
//  ChapterFailureStore.swift
//  Abbay
//

import Foundation

/// Each LibriVox chapter's failed download attempts in a row, kept across launches so a relaunch
/// neither restarts the backoff nor forgets a chapter that is *Failed · Retry* (#148).
///
/// A chapter is identified by its book's archive id and its remote file name, the name its file
/// gets on disk, so a count can't attach to another chapter if a book's chapter order changes.
/// All counts live under one key of the injected store, as `["<book id>/<file name>": count]`.
final class ChapterFailureStore {
    static let key = "downloads.chapterFailures"

    private let store: KeyValueStoring

    init(store: KeyValueStoring = LocalStorage.preferences) {
        self.store = store
    }

    func failures(bookID: String, chapter: ChapterModel) -> Int {
        guard let key = Self.chapterKey(bookID: bookID, chapter: chapter) else { return 0 }
        return counts[key] ?? 0
    }

    /// Stores the count; 0 forgets the chapter.
    func set(_ failures: Int, bookID: String, chapter: ChapterModel) {
        guard let key = Self.chapterKey(bookID: bookID, chapter: chapter) else { return }
        var counts = counts
        guard counts[key] != (failures > 0 ? failures : nil) else { return }
        counts[key] = failures > 0 ? failures : nil
        save(counts)
    }

    /// Forgets every chapter of the book (it was deleted).
    func removeAll(bookID: String) {
        let prefix = "\(bookID)/"
        let counts = counts
        let kept = counts.filter { !$0.key.hasPrefix(prefix) }
        guard kept.count != counts.count else { return }
        save(kept)
    }

    private var counts: [String: Int] {
        store.object(forKey: Self.key) as? [String: Int] ?? [:]
    }

    private func save(_ counts: [String: Int]) {
        if counts.isEmpty {
            store.removeObject(forKey: Self.key)
        } else {
            store.set(counts, forKey: Self.key)
        }
    }

    private static func chapterKey(bookID: String, chapter: ChapterModel) -> String? {
        guard let name = chapter.remoteURL?.lastPathComponent, !name.isEmpty, name != "/" else { return nil }
        return "\(bookID)/\(name)"
    }
}
