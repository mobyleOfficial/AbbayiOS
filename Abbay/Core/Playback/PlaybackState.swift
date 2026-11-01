//
//  PlaybackState.swift
//  Abbay
//

import Foundation
import Observation

/// The slow half of playback: which book is loaded and whether it's playing. It changes only on
/// play, pause or a book switch, never on a clock tick, so rows can read it freely.
///
/// Observation notifies on every set, even with an equal value, so the setters below assign only
/// when the value actually changes.
@Observable
final class PlaybackState {
    private(set) var loadedBook: AudioModel?
    private(set) var isPlaying = false

    /// Books are identified by URL: the player only announces a book when its URL changes.
    func setLoadedBook(_ book: AudioModel?) {
        guard book?.url != loadedBook?.url || (book == nil) != (loadedBook == nil) else { return }
        loadedBook = book
    }

    /// The loaded book's chapters changed (found in its audio, or removed): the one change to the
    /// same book that is announced, since `setLoadedBook` ignores a book with the same URL.
    func setLoadedBookChapters(_ chapters: [ChapterModel], ofBookAt url: URL) {
        guard loadedBook?.url == url else { return }
        loadedBook?.chapters = chapters
    }

    func setIsPlaying(_ isPlaying: Bool) {
        guard isPlaying != self.isPlaying else { return }
        self.isPlaying = isPlaying
    }
}
