//
//  PlayerPresentation.swift
//  Abbay
//

import Observation
import SwiftUI

/// The root's two tabs.
enum RootTab: Hashable {
    case library
    case search
}

/// The one place that presents the details screen (`PlayerView`). A Library row tap, the bar tap
/// and the LibriVox details page's Play all call `open`; the bar's drag up and the details
/// screen's drag down go through `beginInteractive` / `updateInteractive` / `endInteractive`.
/// Nothing presents the player as a sheet.
///
/// Only the expansion overlay's leaves read `progress` and `expansionStart`. The root that owns
/// the tabs, and the bar that carries the drag, must not: a drag that writes them would rebuild
/// the tab view, or the gesture's own view, mid-gesture (see the Task 1 spike).
@MainActor
@Observable
final class PlayerPresentation {
    /// What the details screen shows. It can differ from the loaded book: a row tap opens that
    /// row's book without starting it.
    private(set) var presentedBook: AudioModel?
    /// 0 = collapsed into the bar, 1 = fully open. Animated by the settle, set directly by a drag.
    private(set) var progress: CGFloat = 0
    /// True once the details screen has settled open, false again as soon as a close or a drag
    /// starts. The bar and the tab bar hide on this, not on `progress`: it changes once per open
    /// or close, so the views that read it never re-render during a drag.
    private(set) var isFullyOpen = false
    /// The bar's global frame, written by the bar every time it moves (including each frame of
    /// its insertion transition). The overlay never reads it: it reads `expansionStart`.
    private(set) var barFrame: CGRect?
    /// Where the expansion grows from and collapses back to: the bar's frame, taken once when an
    /// open starts while the bar is visible, or nil for the 56 pt strip along the bottom edge.
    /// Snapshotted rather than tracked, because the bar moves while the screen is open (the
    /// accessory slides down with the hidden tab bar, about 70 pt).
    private(set) var expansionStart: CGRect?

    /// The progress on screen, written by the overlay on every frame it draws (an animated
    /// `progress` is already at its target in the model). A drag that grabs the screen mid-spring
    /// continues from here. Not observed.
    @ObservationIgnored var renderedProgress: CGFloat = 0
    /// The window's size, reported by the overlay; the bottom strip and the drag travel use it.
    @ObservationIgnored private(set) var screenSize: CGSize = .zero

    /// What a drag needs to map its translation to progress.
    struct InteractiveStart: Equatable {
        /// Where the drag continues from: what is on screen now.
        let progress: CGFloat
        /// The distance that covers 0…1: from the start frame's top to the screen's top.
        let travel: CGFloat
    }

    /// Bumped by every `open`, `close` and drag, so a settle that finishes after a newer one
    /// leaves it alone.
    @ObservationIgnored private var generation = 0
    /// Tells whether the bar is visible (a book is loaded) when an open starts. Optional so
    /// tests and previews can omit it: then there is never a bar to grow from.
    @ObservationIgnored private let playback: PlaybackState?

    /// The settle, for taps and releases alike (spec values).
    static let animation: Animation = .spring(response: 0.35, dampingFraction: 0.86)

    init(playback: PlaybackState? = nil) {
        self.playback = playback
    }

    func open(_ book: AudioModel, animated: Bool) {
        generation += 1
        if presentedBook == nil { snapshotExpansionStart() }
        // Books are identified by URL, as everywhere else; the details screen is keyed by it too.
        if presentedBook == nil || presentedBook?.url != book.url { presentedBook = book }
        settleOpen(animated: animated)
    }

    func close(animated: Bool) {
        generation += 1
        let current = generation
        setFullyOpen(false)
        guard animated else {
            set(progress: 0, animated: false, completion: nil)
            clearBook()
            return
        }
        set(progress: 0, animated: true) { [weak self] in
            guard let self, generation == current else { return }
            clearBook()
        }
    }

    // MARK: - Interactive

    /// A finger grabs the bar (`book` is the loaded book) or the details screen (`book` nil). The
    /// screen stops wherever it is, even mid-spring, and the drag continues from there; the bar and
    /// the tab bar come back if it was settled open. Nil when there is nothing to present.
    func beginInteractive(_ book: AudioModel? = nil) -> InteractiveStart? {
        generation += 1
        if presentedBook == nil {
            guard let book else { return nil }
            snapshotExpansionStart()
            presentedBook = book
            renderedProgress = 0
        }
        setFullyOpen(false)
        let current = ExpansionMath.clamp(renderedProgress)
        stop(at: current)
        let start = ExpansionMath.startFrame(bar: expansionStart, screen: screenSize)
        return InteractiveStart(progress: current, travel: start.minY)
    }

    /// The finger moved: no animation, assigned only on change.
    func updateInteractive(_ progress: CGFloat) {
        let value = ExpansionMath.clamp(progress)
        guard self.progress != value else { return }
        self.progress = value
        renderedProgress = value
    }

    /// The finger lifted: settle open or closed with the spring. Closing is `close`, so the
    /// book is released once it lands.
    func endInteractive(open: Bool) {
        guard presentedBook != nil else { return }
        if open {
            generation += 1
            settleOpen(animated: true)
        } else {
            close(animated: true)
        }
    }

    // MARK: - Reports

    /// The system can host the accessory's content more than once around placement changes, and
    /// the copy reports a frame near the top (Task 1 spike, gotcha 4): only a frame in the bottom
    /// half is the bar. Assigned only when it changes.
    func reportBarFrame(_ frame: CGRect, screenHeight: CGFloat) {
        guard frame.minY >= screenHeight / 2, frame != barFrame else { return }
        barFrame = frame
    }

    func reportScreenSize(_ size: CGSize) {
        if screenSize != size { screenSize = size }
    }

    // MARK: - Private

    private func settleOpen(animated: Bool) {
        let current = generation
        set(progress: 1, animated: animated) { [weak self] in
            guard let self, generation == current else { return }
            setFullyOpen(true)
        }
    }

    /// The bar is visible while a book is loaded (the screen isn't settled open when an open
    /// starts). Without it, the expansion grows from the bottom strip.
    private func snapshotExpansionStart() {
        let start = playback?.loadedBook != nil ? barFrame : nil
        if expansionStart != start { expansionStart = start }
    }

    /// Replaces an animation in flight with the value on screen, without animating.
    private func stop(at value: CGFloat) {
        renderedProgress = value
        // At rest the model already holds what is on screen.
        guard progress != value else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            progress = value
        }
    }

    private func setFullyOpen(_ value: Bool) {
        if isFullyOpen != value { isFullyOpen = value }
    }

    private func clearBook() {
        if presentedBook != nil { presentedBook = nil }
    }

    /// Observation notifies on every set, so assign only on change. An unchanged animated value
    /// still runs `completion`, after the same delay a real animation would take.
    private func set(progress value: CGFloat, animated: Bool, completion: (() -> Void)?) {
        guard animated else {
            if progress != value { progress = value }
            renderedProgress = value
            completion?()
            return
        }
        guard progress != value else {
            completion.map(Self.afterAnimation)
            return
        }
        withAnimation(Self.animation) {
            progress = value
        }
        // Timed rather than `withAnimation(completion:)`, so the book is released even when nothing
        // renders the change (off screen, unit tests). The spring settles within this delay.
        completion.map(Self.afterAnimation)
    }

    private static func afterAnimation(_ work: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            work()
        }
    }
}
