//
//  SleepTimer.swift
//  Abbay
//

import Combine
import Foundation
import Observation

/// What the sleep timer was set to (#332).
enum SleepTimerChoice: Hashable {
    /// Seconds of listening.
    case duration(TimeInterval)
    /// The end of the chapter playing (the book's end for a book with no chapters).
    case endOfChapter

    /// Apple Books' set: 5, 10, 15, 30, 45 minutes and an hour.
    static let durations: [TimeInterval] = [300, 600, 900, 1800, 2700, 3600]
}

/// The timer stopped a book: which, and at what book time.
struct SleepTimerStop: Equatable {
    let bookURL: URL
    let stoppedAt: Double
}

enum SleepTimerEvent: Equatable {
    /// The listener set, changed or turned off the timer, on the book loaded then.
    case set(bookURL: URL?)
    /// The timer stopped a book: it ran out, or the book ended while it was set.
    case stopped(SleepTimerStop)
}

/// Playback events, forwarded on main by `PlaybackCenter` to whoever needs them beside the views.
@MainActor
protocol PlaybackEventObserving: AnyObject {
    func playingChanged(_ isPlaying: Bool)
    func timeChanged(bookTime: Double)
    func bookEnded()
    func bookUnloaded()
    func chaptersChanged()
}

extension PlaybackEventObserving {
    func playingChanged(_ isPlaying: Bool) {}
    func timeChanged(bookTime: Double) {}
    func bookEnded() {}
    func bookUnloaded() {}
    func chaptersChanged() {}
}

/// The sleep timer (#332). It belongs to playback, not to a screen or a book: built once beside
/// `PlaybackCenter`, it keeps counting with the player closed, in the background and locked, and
/// follows a book switch.
///
/// It counts listening time only: a pause (by hand, a call, anything) holds the count and play
/// resumes it; only Off cancels it. In its last `fadeDuration` it ramps Abbay's volume down through
/// the player's fade level (never the saved volume, never the system's), then pauses and gives the
/// level back. A volume change during the ramp ends the ramp; the pause still comes.
@MainActor
@Observable
final class SleepTimer: PlaybackEventObserving {
    private(set) var choice: SleepTimerChoice?

    @ObservationIgnored private let player: PlayerProtocol
    @ObservationIgnored private let loadedBook: @MainActor () -> AudioModel?
    @ObservationIgnored private let scheduler: SleepTimerScheduling
    @ObservationIgnored private let fadeDuration: TimeInterval
    @ObservationIgnored private let firstDurationOverride: TimeInterval?
    @ObservationIgnored private let subject = PassthroughSubject<SleepTimerEvent, Never>()

    @ObservationIgnored private var isPlaying: Bool
    /// A duration's listening time left, as of `countedSince` (or now, while paused).
    private var banked: TimeInterval = 0
    /// When playing last started under a duration; nil while paused.
    private var countedSince: TimeInterval?
    @ObservationIgnored private var fade: Fade?
    @ObservationIgnored private var fadeStart: AnyCancellable?

    /// A running fade: when it pauses, its ramp's next step, and the level it last set (to notice
    /// the listener changing the volume).
    private struct Fade {
        let start: TimeInterval
        let end: TimeInterval
        var lastLevel: Double?
        var isOverridden = false
        var step: AnyCancellable?
        var finish: AnyCancellable?
    }

    private static let rampStep: TimeInterval = 0.25

    init(
        player: PlayerProtocol,
        loadedBook: @escaping @MainActor () -> AudioModel?,
        scheduler: SleepTimerScheduling = TaskSleepTimerScheduler(),
        fadeDuration: TimeInterval = 5,
        firstDurationOverride: TimeInterval? = nil
    ) {
        self.player = player
        self.loadedBook = loadedBook
        self.scheduler = scheduler
        self.fadeDuration = fadeDuration
        self.firstDurationOverride = firstDurationOverride
        self.isPlaying = player.isPlaying(player.url)
    }

    var events: AnyPublisher<SleepTimerEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    /// What the menu offers for `book`: *When current chapter ends* only for a book with chapters.
    func choices(for book: AudioModel?) -> [SleepTimerChoice] {
        let durations = SleepTimerChoice.durations.map(SleepTimerChoice.duration)
        guard let book, !book.chapters.isEmpty else { return durations }
        return [.endOfChapter] + durations
    }

    /// A duration's listening time left; nil when Off or set to the end of the chapter.
    func remaining() -> TimeInterval? {
        guard case .duration = choice else { return nil }
        guard let countedSince else { return banked }
        return max(banked - (scheduler.now - countedSince), 0)
    }

    /// Sets, changes (restarting the count) or, with nil, turns off the timer.
    func set(_ choice: SleepTimerChoice?) {
        cancel()
        self.choice = choice
        if case let .duration(seconds) = choice {
            banked = seconds == SleepTimerChoice.durations.first ? firstDurationOverride ?? seconds : seconds
            countedSince = isPlaying ? scheduler.now : nil
        }
        subject.send(.set(bookURL: loadedBook()?.url ?? player.url))
        schedule()
    }

    // MARK: - PlaybackEventObserving

    func playingChanged(_ isPlaying: Bool) {
        guard isPlaying != self.isPlaying else { return }
        self.isPlaying = isPlaying
        guard choice != nil else { return }
        if !isPlaying, fade != nil {
            // Paused while fading: the timer did its job.
            stop()
            return
        }
        if case .duration = choice {
            if isPlaying {
                countedSince = scheduler.now
            } else if let countedSince {
                banked = max(banked - (scheduler.now - countedSince), 0)
                self.countedSince = nil
            }
        }
        schedule()
    }

    func bookEnded() {
        guard choice != nil else { return }
        stop()
    }

    func bookUnloaded() {
        guard choice != nil else { return }
        cancel()
        choice = nil
    }

    // MARK: - Scheduling

    /// When playback should pause, in scheduler time; nil while paused.
    private var deadline: TimeInterval? {
        guard isPlaying else { return nil }
        switch choice {
        case .duration:
            return countedSince.map { $0 + banked }
        case .endOfChapter, nil:
            return nil
        }
    }

    private func schedule() {
        fadeStart = nil
        guard fade == nil, let deadline else { return }
        let untilFade = deadline - fadeDuration - scheduler.now
        if untilFade <= 0 {
            beginFade(endingAt: deadline)
        } else {
            fadeStart = scheduler.after(untilFade) { [weak self] in
                self?.beginFade(endingAt: deadline)
            }
        }
    }

    private func beginFade(endingAt end: TimeInterval) {
        fadeStart = nil
        fade = Fade(start: scheduler.now, end: end)
        fade?.finish = scheduler.after(end - scheduler.now) { [weak self] in
            self?.stop()
        }
        rampStep()
    }

    private func rampStep() {
        guard var fade, !fade.isOverridden else { return }
        if let lastLevel = fade.lastLevel, player.fadeLevel != lastLevel {
            // The listener changed the volume: their level wins until the pause.
            fade.isOverridden = true
            fade.step = nil
            self.fade = fade
            return
        }
        let span = fade.end - fade.start
        let level = span > 0 ? max(min((fade.end - scheduler.now) / span, 1), 0) : 0
        player.setFadeLevel(level)
        fade.lastLevel = player.fadeLevel
        let next = scheduler.now + Self.rampStep
        fade.step = next < fade.end
            ? scheduler.after(Self.rampStep) { [weak self] in self?.rampStep() }
            : nil
        self.fade = fade
    }

    // MARK: - Ending

    /// Ran out, paused mid-fade, or the book ended: Off, paused, the level back, and the stop
    /// announced for *back to where you fell asleep*.
    private func stop() {
        let silent = fade.map { !$0.isOverridden } ?? false
        if silent {
            player.setFadeLevel(0)
        }
        let bookURL = loadedBook()?.url ?? player.url
        let stoppedAt = player.currentTime
        // Silent until paused: the level comes back only after the pause.
        cancel(restoringLevel: false)
        choice = nil
        if isPlaying {
            player.pause()
        }
        if silent {
            player.setFadeLevel(1)
        }
        if let bookURL {
            subject.send(.stopped(SleepTimerStop(bookURL: bookURL, stoppedAt: stoppedAt)))
        }
    }

    /// Drops whatever is scheduled and, unless told not to, gives back a faded level.
    private func cancel(restoringLevel: Bool = true) {
        fadeStart = nil
        if restoringLevel, let fade, !fade.isOverridden, player.fadeLevel != 1 {
            player.setFadeLevel(1)
        }
        fade = nil
        countedSince = nil
        banked = 0
    }
}
