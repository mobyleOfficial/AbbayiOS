//
//  PlayerViewModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 10/07/23.
//

import Foundation

/// Adapts the app-wide stores for the details screen. It holds no player subscriptions and no
/// download sink: everything it shows is read from `PlaybackState`, `PlaybackClock` and the book's
/// `BookDownloadEntry`, so SwiftUI tracks exactly what each part of the screen reads.
///
/// - The **loaded book** (the one in the player) shows the player's state: `isPlaying` from
///   `PlaybackState`, the time and chapter from `PlaybackClock`. Only the screen's leaves pass the
///   clock in, so its chrome never re-renders on a tick.
/// - **Any other book** (a row tap opens a book without starting it) shows its saved position.
///   Its transport does nothing until Play loads it, so it can't move the loaded book.
/// - Opened on the loaded book, the screen **follows the loaded book**: if Siri or CarPlay switches
///   books while it's open, it shows the new one. Pressing Play on another book does the same.
@MainActor
final class PlayerViewModel {
    private let presented: AudioModel
    private let state: PlaybackState
    private let player: PlayerProtocol?
    private let downloads: DownloadStateStore?
    /// Latched the first time the presented book is seen loaded; from then on the screen shows
    /// whatever is loaded. A cache of what `PlaybackState` already said, so it isn't observed, and
    /// it isn't read in `init`: the view model is built in a parent's body, which must not start
    /// depending on `loadedBook`.
    private var followsLoadedBook = false

    init(_ book: AudioModel, state: PlaybackState, player: PlayerProtocol?, downloads: DownloadStateStore?) {
        presented = book
        self.state = state
        self.player = player
        self.downloads = downloads
    }

    // MARK: - What the screen shows

    /// The loaded book's model when this screen is (or follows) the loaded book, else the presented one.
    var book: AudioModel {
        loadedBookShown ?? presented
    }

    var isLoaded: Bool {
        loadedBookShown != nil
    }

    var isPlaying: Bool {
        isLoaded && state.isPlaying
    }

    /// Non-nil only for a LibriVox book. Its `state` is nil once the download is complete.
    var downloadEntry: BookDownloadEntry? {
        guard let id = book.librivoxID else { return nil }
        return downloads?.entry(for: id)
    }

    /// The clock for the loaded book, the saved position otherwise. Call it only from a leaf: it
    /// makes the caller depend on every tick.
    func bookTime(in clock: PlaybackClock) -> Double {
        isLoaded ? clock.bookTime : book.currentTime
    }

    /// Reads `PlaybackClock.currentChapter` only, so the caller re-renders per chapter, not per tick.
    func currentChapter(in clock: PlaybackClock) -> Int {
        isLoaded ? clock.currentChapter : book.currentChapter(for: book.currentTime) ?? 0
    }

    // MARK: - Transport

    /// Resumes the loaded book, or loads this one; once the player announces it, the screen
    /// follows it.
    func play() {
        var book = book
        player?.play(&book)
    }

    func pause() {
        guard isLoaded else { return }
        player?.pause()
    }

    func forward(withSeconds seconds: Double) {
        guard isLoaded else { return }
        player?.forward(withSeconds: seconds)
    }

    func backward(withSeconds seconds: Double) {
        guard isLoaded else { return }
        player?.backward(withSeconds: seconds)
    }

    func seek(_ seconds: Double) {
        guard isLoaded else { return }
        player?.seek(seconds)
    }

    // MARK: - Speed

    /// The shown book's speed. Read from the settings (observable), which the player also writes,
    /// so a change from the lock screen shows here too.
    func speed(in settings: AppSettings) -> Double {
        settings.speed(for: book.url)
    }

    /// The loaded book changes speed at once; another book just remembers it for when it plays.
    func setSpeed(_ speed: Double, in settings: AppSettings) {
        if isLoaded, let player {
            player.setPlaybackRate(speed)
        } else {
            settings.setSpeed(speed, for: book.url)
        }
    }

    /// A chapter row seeks to its start, only while playing, as before.
    /// A chapter's "Failed · Retry" status: restarts its download now. Works whether or not the
    /// book is loaded, since it touches only the download.
    func retryChapter(_ index: Int) {
        guard let id = book.librivoxID else { return }
        downloads?.retry(chapterIndex: index, bookID: id)
    }

    func selectChapter(_ index: Int) {
        let chapters = book.chapters
        guard isPlaying, chapters.indices.contains(index) else { return }
        player?.seek(chapters[index].startTime)
    }

    // MARK: - Private

    /// The loaded book, when this screen shows it.
    private var loadedBookShown: AudioModel? {
        guard let loaded = state.loadedBook else { return nil }
        if !followsLoadedBook, presented.url != nil, loaded.url == presented.url {
            followsLoadedBook = true
        }
        return followsLoadedBook ? loaded : nil
    }
}
