//
//  RowProgressView.swift
//  Abbay
//

import SwiftUI

/// The loaded row's live detail line. The only row view that reads `PlaybackClock`, and
/// `MediaView` inserts it only when `PlaybackState.loadedBook` is this row's book, so idle rows
/// never depend on the clock.
struct RowProgressView: View {
    @Environment(PlaybackClock.self)
    private var clock
    private let book: AudioModel

    init(book: AudioModel) {
        self.book = book
    }

    var body: some View {
        Text(Self.detailLine(book: book, clock: clock))
    }

    /// Reads only what the line shows: a chaptered book shows the chapter, so a tick within the
    /// same chapter costs nothing; a book without chapters shows the time left, so it follows
    /// `bookTime`.
    static func detailLine(book: AudioModel, clock: PlaybackClock) -> String {
        if book.chapters.isEmpty {
            return MediaView.detailLine(book: book, chapterIndex: 0, bookTime: clock.bookTime)
        }
        return MediaView.detailLine(book: book, chapterIndex: clock.currentChapter, bookTime: 0)
    }
}
