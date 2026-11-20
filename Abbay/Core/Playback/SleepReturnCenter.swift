//
//  SleepReturnCenter.swift
//  Abbay
//

import Combine
import Foundation
import Observation

/// *Back to where you fell asleep* (#332): when the sleep timer stops a book, the place the listener
/// was last certainly awake is kept for that book (`AppSettings.sleepReturnSpot`), across launches,
/// and the player offers to go back there.
///
/// The spot goes when it is used or dismissed, when a new timer is set on the book, when the book
/// starts playing more than `restartDistance` from where the timer stopped it (a chapter tap, a long
/// scrub), or once `listeningLimit` of the book has played past that point. Pressing Play at or near
/// the stop keeps it: half asleep, the listener may do that on the lock screen before seeing it.
///
/// Observable only so views can find it in the environment; what they show comes from `AppSettings`.
@MainActor
@Observable
final class SleepReturnCenter: PlaybackEventObserving {
    /// Book seconds from the stop beyond which starting playback means the listener moved on.
    static let restartDistance: Double = 300
    /// Book seconds played past the stop after which the spot is stale.
    static let listeningLimit: Double = 1800

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let timer: SleepTimer
    @ObservationIgnored private let player: PlayerProtocol
    @ObservationIgnored private let savePosition: SavePlaybackPositionUseCaseProtocol
    @ObservationIgnored private let loadedURL: @MainActor () -> URL?
    @ObservationIgnored private var cancellable: AnyCancellable?
    /// Only listening counts towards `listeningLimit`: a scrub or skip while paused doesn't.
    @ObservationIgnored private var isPlaying = false

    /// `nonisolated`, like `PlaybackCenter`'s, so the dependency container (and the tests' container,
    /// sometimes built off the main thread) can build it. Timer events are moved onto main.
    nonisolated init(
        settings: AppSettings,
        timer: SleepTimer,
        player: PlayerProtocol,
        savePosition: SavePlaybackPositionUseCaseProtocol = SavePlaybackPositionUseCase(),
        loadedURL: @escaping @MainActor () -> URL?
    ) {
        self.settings = settings
        self.timer = timer
        self.player = player
        self.savePosition = savePosition
        self.loadedURL = loadedURL
        cancellable = timer.events.sink { [weak self] event in
            Self.onMain { self?.receive(event) }
        }
    }

    /// The spot to offer on `url`'s player, if any. Reads observable settings, so a view follows it.
    func spot(for url: URL?) -> SleepReturnSpot? {
        settings.sleepReturnSpot(for: url)
    }

    /// Goes back to the spot without playing: a loaded book seeks there, any other book has its saved
    /// position moved there (it opens there next). Returns where it went, nil without a spot.
    @discardableResult
    func goBack(for url: URL?) -> Double? {
        guard let spot = spot(for: url) else { return nil }
        if let url, url == loadedURL() {
            player.seek(spot.returnTo)
        } else {
            savePosition.execute(url: url, currentTime: spot.returnTo, bookmarkData: nil)
        }
        settings.setSleepReturnSpot(nil, for: url)
        return spot.returnTo
    }

    func dismiss(for url: URL?) {
        settings.setSleepReturnSpot(nil, for: url)
    }

    // MARK: - The timer

    private func receive(_ event: SleepTimerEvent) {
        switch event {
        case let .stopped(stop):
            settings.setSleepReturnSpot(
                SleepReturnSpot(returnTo: stop.lastAwakeAt, stoppedAt: stop.stoppedAt),
                for: stop.bookURL
            )
        case let .set(bookURL):
            // A new night; turning the timer off isn't one.
            if timer.choice != nil {
                settings.setSleepReturnSpot(nil, for: bookURL)
            }
        }
    }

    /// Synchronously on main (the timer sends there); hops there otherwise.
    private nonisolated static func onMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(work) }
        }
    }

    // MARK: - PlaybackEventObserving

    func playingChanged(_ isPlaying: Bool) {
        self.isPlaying = isPlaying
        guard isPlaying, let url = loadedURL(), let spot = spot(for: url) else { return }
        if abs(player.currentTime - spot.stoppedAt) > Self.restartDistance {
            settings.setSleepReturnSpot(nil, for: url)
        }
    }

    func timeChanged(bookTime: Double) {
        guard isPlaying, let url = loadedURL(), let spot = spot(for: url) else { return }
        if bookTime >= spot.stoppedAt + Self.listeningLimit {
            settings.setSleepReturnSpot(nil, for: url)
        }
    }
}
