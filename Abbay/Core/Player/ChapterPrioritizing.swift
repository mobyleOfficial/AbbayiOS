//
//  ChapterPrioritizing.swift
//  Abbay
//

import Foundation

/// Tells the downloader which chapter the listener needs next, so it can move that file to the
/// front of the queue. The player calls it whenever it loads or advances to a chapter.
protocol ChapterPrioritizing: AnyObject {
    func prioritize(chapterIndex: Int, ofBookID id: String)
}

/// Default until the download manager exists: streaming covers chapters that aren't on disk yet.
final class NoopChapterPrioritizer: ChapterPrioritizing {
    func prioritize(chapterIndex: Int, ofBookID id: String) {}
}
