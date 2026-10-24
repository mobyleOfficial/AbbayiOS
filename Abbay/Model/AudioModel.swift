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
    var url: URL?
    var bookmarkData: Data?
    /// The book's archive.org identifier (e.g. `alice_in_wonderland_librivox`), not a LibriVox
    /// catalog ID: not every archive item has one. Named for the source; nil for imported files.
    var librivoxID: String?
    var allowsCellularDownload = false
    var isDownloadPaused = false
    var totalBytes: Int64 = 0
    /// The URL the book's Core Data row is saved under, when the model was loaded from the store.
    /// It differs from `url` once the file has moved: `url` is where the bookmark resolves now
    /// (what plays), this is the row's key. Nil for a book not loaded from the store (#176).
    var storedURL: URL?

    /// The key of the book's row: what every row operation (save, delete, position write) must
    /// look the book up by. A moved book's `url` matches no row.
    var rowURL: URL? {
        storedURL ?? url
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
