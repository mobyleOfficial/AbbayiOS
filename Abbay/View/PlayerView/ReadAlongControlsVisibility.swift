//
//  ReadAlongControlsVisibility.swift
//  Abbay
//

import Foundation
import Observation

/// Whether the read-along controls show (#192, owner's follow-up: "lets prioritize immersion"):
/// the square's language label and expand button, the full screen's label, play/pause and collapse.
/// Visible when the text appears, hidden after `delay` with no interaction; a tap brings them back,
/// and every interaction starts the delay again.
///
/// Pinned visible while something needs them (`isPinned(voiceOver:menuOpen:state:covered:)`): no
/// hide is scheduled then, and they come back if they were hidden.
///
/// One hide is scheduled per interaction, a sleeping task cancelled by the next one, rather than a
/// clock polled on every frame: only the view that reads `isHidden` re-renders, and only when it
/// flips.
@MainActor
@Observable
final class ReadAlongControlsVisibility {
    /// Runs `action` after `delay`; returns what cancels it. Injected so tests run the delay by hand.
    typealias Schedule = @MainActor (Duration, @escaping @MainActor () -> Void) -> () -> Void

    /// The owner's 3 s, unless a UI test launch set another (`-readAlongControlsHideAfter`).
    static let defaultDelay: Duration = .seconds(3)
    static let launchDelay: Duration = DebugOverrides.readAlongControlsHideAfter() ?? defaultDelay

    private(set) var isHidden = false

    @ObservationIgnored
    private(set) var isPinned = false
    @ObservationIgnored
    private let delay: Duration
    @ObservationIgnored
    private let schedule: Schedule
    @ObservationIgnored
    private var cancelHide: (() -> Void)?

    init(delay: Duration = launchDelay, schedule: @escaping Schedule = ReadAlongControlsVisibility.sleeping) {
        self.delay = delay
        self.schedule = schedule
    }

    /// The text appeared, or the user touched it: the controls show, and hide again after the delay
    /// unless something pins them.
    func reveal() {
        cancel()
        if isHidden { isHidden = false }
        guard !isPinned else { return }
        cancelHide = schedule(delay) { [weak self] in
            self?.cancelHide = nil
            self?.isHidden = true
        }
    }

    /// Pinned: they show and stay. Unpinned: the delay starts again. The same value again (a
    /// re-render) changes nothing.
    func setPinned(_ pinned: Bool) {
        guard pinned != isPinned else { return }
        isPinned = pinned
        reveal()
    }

    /// The text left the screen: nothing is left to hide.
    func stop() {
        cancel()
    }

    private func cancel() {
        cancelHide?()
        cancelHide = nil
    }

    /// The controls must stay: VoiceOver users would lose them; the language menu hangs off the
    /// label; while the text isn't ready (*Preparing*, *Downloading*, *Not available*, *must be
    /// downloaded*, *Couldn't make*) the label may be what's needed; and while something covers
    /// them (the chapter panel, the full screen) they are out of the way already, and come back
    /// with a fresh delay when it goes.
    static func isPinned(voiceOver: Bool, menuOpen: Bool, state: ReadAlongState, covered: Bool) -> Bool {
        voiceOver || menuOpen || state != .ready || covered
    }

    /// The real clock: a task that sleeps, then acts unless it was cancelled meanwhile (also after
    /// the sleep ended, while it waited for the main actor).
    static func sleeping(_ delay: Duration, _ action: @escaping @MainActor () -> Void) -> () -> Void {
        let task = Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
        }
        return { task.cancel() }
    }
}
