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
/// and the LibriVox details page's Play all call `open`; nothing presents the player as a sheet.
///
/// Only the overlay that draws the details screen reads `progress`. The root that owns the tabs
/// must not, or a drag that writes it would rebuild the tab view mid-gesture (see the Task 1 spike).
@MainActor
@Observable
final class PlayerPresentation {
    /// What the details screen shows. It can differ from the loaded book: a row tap opens that
    /// row's book without starting it.
    private(set) var presentedBook: AudioModel?
    /// 0 = collapsed into the bar, 1 = fully open.
    var progress: CGFloat = 0
    /// True once the details screen has settled open, false again as soon as a close starts. The
    /// bar hides on this, not on `progress`: it changes once per open or close, so the views that
    /// read it (the root's accessory, the docked bar's container) never re-render during a drag.
    private(set) var isFullyOpen = false
    /// The bar's global frame, where the expansion starts. Written by the bar, read by the overlay.
    private(set) var barFrame: CGRect?

    /// Bumped by every `open` and `close`, so a collapse that finishes after a reopen leaves the
    /// new book alone.
    @ObservationIgnored private var generation = 0

    static let animation: Animation = .spring(duration: 0.4, bounce: 0)

    func open(_ book: AudioModel, animated: Bool) {
        generation += 1
        // Books are identified by URL, as everywhere else; the details screen is keyed by it too.
        if presentedBook == nil || presentedBook?.url != book.url { presentedBook = book }
        let current = generation
        set(progress: 1, animated: animated) { [weak self] in
            guard let self, generation == current else { return }
            setFullyOpen(true)
        }
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

    /// The system can host the accessory's content more than once around placement changes, and
    /// the copy reports a frame near the top (Task 1 spike, gotcha 4): only a frame in the bottom
    /// half is the bar. Assigned only when it changes.
    func reportBarFrame(_ frame: CGRect, screenHeight: CGFloat) {
        guard frame.minY >= screenHeight / 2, frame != barFrame else { return }
        barFrame = frame
    }

    // MARK: - Private

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
        // renders the change (off screen, unit tests). The spring settles within its duration.
        completion.map(Self.afterAnimation)
    }

    private static func afterAnimation(_ work: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            work()
        }
    }
}
