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

    // MARK: - Deliveries
    private func receive(book: AudioModel) {
        let isNewBook = book.url != state.loadedBook?.url
        state.setLoadedBook(book)
        // A new book starts at its saved position: the player seeks there right after announcing it.
        let bookTime = isNewBook ? book.currentTime : clock.bookTime
        Self.apply(bookTime: bookTime, book: book, to: clock)
    }

    private func receive(time: CMTime) {
        Self.apply(bookTime: time.seconds, book: state.loadedBook, to: clock)
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
