//
//  AudioModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 19/06/23.
//

import Foundation

struct AudioModel {
    var title = String()
    var albumName = String()
    var artist = String()
    var duration: Double = .zero
    var currentTime: Double = .zero
    var imageData: Data?
    var chapters = [ChapterModel]()
    /// The book's identity: the URL its Core Data row is saved under (a new book's file URL, or a
    /// LibriVox `librivox://` URL). It doesn't change when the file moves; `fileURL` does.
    var url: URL?
    var bookmarkData: Data?
    /// The book's archive.org identifier (e.g. `alice_in_wonderland_librivox`), not a LibriVox
    /// catalog ID: not every archive item has one. Named for the source; nil for imported files.
    var librivoxID: String?
    var allowsCellularDownload = false
    var isDownloadPaused = false
    var totalBytes: Int64 = 0
    /// Where the book's file is now, when that is not `url`: its bookmark resolved somewhere else
    /// (the file moved in Files, an iCloud re-sync, a reinstall that moved the bundle). Set only
    /// when a book is mapped from the store; nil for one whose file is still at `url` (#186).
    var resolvedURL: URL?

    /// What to open to play the book: where its file is now. Only for reaching the file (the
    /// player item, its security scope, a new bookmark, whether it is still there). Everything that
    /// identifies the book, from its Core Data row to last played, Siri's ids, speeds, CarPlay's
    /// playing row and the library's rows, uses `url`, which stays the URL the row is saved under
    /// (#176, #186).
    var fileURL: URL? {
        resolvedURL ?? url
    }

    var isLibriVox: Bool {
        librivoxID != nil
    }

    /// The index of the chapter that holds `time`: the last one starting at or before it. Clamped,
    /// so a time before the first chapter reads as the first and one at or past the end as the
    /// last (#101). `nil` when there is no chapter to report (the book has none, or `time` isn't a
    /// number), which callers must not mistake for chapter 0.
    ///
    /// No lead-in: `Player` seeks never land before their target, so a skip to a chapter's start
    /// reads as that chapter.
    func currentChapter(for time: Double) -> Int? {
        guard !chapters.isEmpty, time.isFinite else { return nil }
        return chapters.lastIndex { $0.startTime <= time } ?? 0
    }
}
