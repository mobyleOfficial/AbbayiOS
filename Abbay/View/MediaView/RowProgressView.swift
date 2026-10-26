//
//  RowProgressView.swift
//  Abbay
//

import SwiftUI

/// The loaded cell's live status line and progress bar. The only cell view that reads
/// `PlaybackClock`, and `MediaView` inserts it only when `PlaybackState.loadedBook` is this cell's
/// book, so idle cells never depend on the clock.
struct RowProgressView: View {
    @Environment(PlaybackClock.self)
    private var clock
    private let book: AudioModel
    private let namespace: String

    init(book: AudioModel, namespace: String) {
        self.book = book
        self.namespace = namespace
    }

    var body: some View {
        MediaView.statusViews(
            line: Self.detailLine(book: book, clock: clock),
            fraction: MediaView.progressFraction(book: book, bookTime: clock.bookTime),
            namespace: namespace
        )
    }

    /// Reads only what the line shows: a chaptered book shows the chapter, so a tick within the
    /// same chapter costs nothing; a book without chapters shows the time left, so it follows
    /// `bookTime`.
    static func detailLine(book: AudioModel, clock: PlaybackClock) -> String {
        if book.chapters.isEmpty {
            return MediaView.detailLine(book: book, chapterIndex: 0, bookTime: clock.bookTime)
        }
        return MediaView.chapterLine(book: book, chapterIndex: clock.currentChapter)
    }
}
