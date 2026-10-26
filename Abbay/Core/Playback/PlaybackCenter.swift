//
//  PlaybackCenter.swift
//  Abbay
//

import AVFoundation
import Combine
import Foundation

/// The one app-wide playback source. It subscribes to the player's three publishers (play URL,
/// time, playing status) exactly once and feeds `state` (slow) and `clock` (ticking). Views read
/// those two objects instead of subscribing to the player themselves; actions go straight to
/// `player`.
@MainActor
final class PlaybackCenter {
    let state: PlaybackState
    let clock: PlaybackClock
    let player: PlayerProtocol
    private var cancellables = Set<AnyCancellable>()
    /// Set by a switch to a book with a saved position: until the player's seek there lands, the
    /// new item still reports ~0, which must not overwrite the seeded `bookTime`.
    private var pendingSeekTarget: Double?

    /// A tick below this, while a seek is pending, is the new item's start, not a real position.
    private static let startTolerance: Double = 1

    /// `nonisolated` so `DependencyContainer` (and the tests' containers) can build it from any
    /// context. Deliveries are moved onto the main actor in `onMain`.
    nonisolated init(
        player: PlayerProtocol,
        loadAudio: LoadAudioUseCaseProtocol = LoadAudioUseCase()
    ) {
        self.player = player
        let state = PlaybackState()
        let clock = PlaybackClock()
        self.state = state
        self.clock = clock

        // A book can already be loaded (Siri, CarPlay, or a center rebuilt after launch): the play
        // event happened before this subscribed, so seed from the player (#116).
        if let url = player.url {
            let book = loadAudio.execute(url: url) ?? AudioModel(url: url)
            state.setLoadedBook(book)
            // The same mapping as `isPlayingPublisher` (buffering counts, no item to play doesn't).
            state.setIsPlaying(player.isPlaying(url))
            Self.apply(bookTime: player.currentTime, book: book, to: clock)
        }

        var cancellables = Set<AnyCancellable>()
        player.playUrlSubjectPublisher
            .sink { [weak self] book in
                Self.onMain { self?.receive(book: book) }
            }
            .store(in: &cancellables)
        player.currentTimePublisher
            .sink { [weak self] time in
                Self.onMain { self?.receive(time: time) }
            }
            .store(in: &cancellables)
        player.isPlayingPublisher
            .sink { [weak self] isPlaying in
                Self.onMain { self?.state.setIsPlaying(isPlaying) }
            }
            .store(in: &cancellables)
        self.cancellables = cancellables
    }

    // MARK: - Actions
    /// The loaded book was deleted: unload it from the player and forget it here, so the bar and
    /// the row's playing state go away. The player announces no event for this, hence the reset.
    func unload() {
        player.unload()
        pendingSeekTarget = nil
        state.setLoadedBook(nil)
        state.setIsPlaying(false)
        clock.update(bookTime: 0, currentChapter: 0)
    }

    // MARK: - Deliveries
    private func receive(book: AudioModel) {
        let isNewBook = book.url != state.loadedBook?.url
        state.setLoadedBook(book)
        // A new book starts at its saved position: the player seeks there right after announcing it.
        let bookTime = isNewBook ? book.currentTime : clock.bookTime
        if isNewBook {
            pendingSeekTarget = book.currentTime >= Self.startTolerance ? book.currentTime : nil
        }
        Self.apply(bookTime: bookTime, book: book, to: clock)
    }

    /// Two ticks are dropped, so the bar's time never flickers or resets on a switch:
    /// - one from an item that isn't the loaded book's: `play` off the main thread (SiriKit)
    ///   switches the item before its announcement hops here, and the tick would be read
    ///   against the old book;
    /// - a ~0 tick right after a switch, before the seek to the saved position lands. The first
    ///   tick that isn't ~0 ends that window, so a later jump to the start still shows.
    private func receive(time: CMTime) {
        guard player.url == state.loadedBook?.url else { return }
        let seconds = time.seconds
        guard seconds.isFinite else { return }
        if pendingSeekTarget != nil {
            if seconds < Self.startTolerance { return }
            pendingSeekTarget = nil
        }
        Self.apply(bookTime: seconds, book: state.loadedBook, to: clock)
    }

    private nonisolated static func apply(bookTime: Double, book: AudioModel?, to clock: PlaybackClock) {
        guard bookTime.isFinite else { return }
        clock.update(bookTime: bookTime, currentChapter: book?.currentChapter(for: bookTime) ?? 0)
    }

    /// Runs synchronously when already on the main thread (the player's publishers deliver there),
    /// and hops to it otherwise, e.g. a `play` started off the main thread.
    private nonisolated static func onMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(work) }
        }
    }
}
