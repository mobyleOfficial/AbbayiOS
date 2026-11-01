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

/// The one place that presents the details screen (`PlayerView`). A Library cell or Continue card
/// tap, the bar tap and the LibriVox details page's Play all call `open`; the bar's drag up and the
/// details screen's drag down go through `beginInteractive` / `updateInteractive` /
/// `endInteractive`. Nothing presents the player as a sheet.
///
/// An open grows from where the tap happened (#241): the tapped cover (`open(_:animated:from:)`
/// with the cover's `ExpansionSourceID`, whose frame the cover reports), else the bar, else the
/// bottom strip; the close lands back there (`ExpansionMath.origin`).
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
    /// Whether the chapters are open for the presented book: the compact panel over the player in
    /// one pane, the chapters pane in browsing's place when the window is split (#255). Kept here,
    /// not in the player, so a fold or a resize shows the same chapters in the other form.
    private(set) var isShowingChapters = false
    /// The presented player's read-along text, shown over the whole window (#192): drawn by the
    /// root (`ReadAlongFullScreenHost`) so it covers both panes when split. Never remembered: the
    /// player always opens with the square. It ends with the player, with another book, and with
    /// a change of split (the other layout's player has a session of its own).
    private(set) var readAlongFullScreen: ReadAlongFullScreen?
    /// "Resumed at 3:20 · Start over", after a chapter tap resumed partway in (#299). Here so the
    /// panel that took the tap and the player that shows the prompt share it; the player shows it
    /// only for its own book, and dismisses it after `ResumePrompt.duration`.
    private(set) var resumePrompt: ResumePrompt?
    /// The bar's global frame, written by the bar every time it moves (including each frame of
    /// its insertion transition). The overlay never reads it: it reads `expansionStart`.
    private(set) var barFrame: CGRect?
    /// Where the expansion grows from and collapses back to: the tapped cover, the bar's frame
    /// (taken once when an open starts while the bar is visible), or the 56 pt strip along the
    /// bottom edge. Snapshotted rather than tracked, because the bar moves while the screen is open
    /// (the accessory slides down with the hidden tab bar, about 70 pt). A close re-reads the
    /// cover's frame, and lands on the bar instead once the cover is off screen.
    private(set) var origin: ExpansionOrigin = .bottomStrip

    /// The origin's frame: nil for the bottom strip.
    var expansionStart: CGRect? { origin.frame }

    /// The progress on screen, written by the overlay on every frame it draws (an animated
    /// `progress` is already at its target in the model). A drag that grabs the screen mid-spring
    /// continues from here. Not observed.
    @ObservationIgnored var renderedProgress: CGFloat = 0
    /// The window is split (`PaneLayout.split`): the player is a pane beside browsing, so an open
    /// or a close is immediate (the pane animates its own insertion) and nothing expands from a
    /// cover or the bar. Set by the root when its layout changes (`layoutChanged`).
    @ObservationIgnored private(set) var usesPanes = false
    /// The window's size, reported by the overlay; the bottom strip and the drag travel use it.
    @ObservationIgnored private(set) var screenSize: CGSize = .zero

    /// What a drag needs to map its translation to progress.
    struct InteractiveStart: Equatable {
        /// Where the drag continues from: what is on screen now.
        let progress: CGFloat
        /// The distance that covers 0…1: from the start frame's top to the screen's top.
        let travel: CGFloat
        /// Identifies this interaction: it ends with any `open`, `close`, settle or newer drag.
        let id: Int
    }

    /// Bumped by every `open`, `close` and drag, so a settle that finishes after a newer one
    /// leaves it alone.
    @ObservationIgnored private var generation = 0
    /// Bumped each time a presentation starts from closed (an open, or a drag up from the bar).
    /// Per-presentation state (the details screen's view model) is keyed by it.
    @ObservationIgnored private(set) var presentationID = 0
    /// Whether `barFrame` was reported with the tab bar showing. While the screen is settled open
    /// the tab bar is hidden and the accessory slides down with it (about 70 pt), so a frame
    /// reported then isn't where the bar rests.
    @ObservationIgnored private var barFrameIsResting = false
    /// A collapse started with no bar to land on (opened from the bottom strip) while a book is
    /// loaded: the bar is coming back with the tab bar, and the start is taken once it rests.
    @ObservationIgnored private var awaitingRestingBar = false
    /// That collapse was released before the bar came to rest: the panel lands on the bar's frames
    /// as they are reported, rather than waiting for a rest that can come after the landing (#130).
    @ObservationIgnored private var landsOnMovingBar = false
    @ObservationIgnored private var restingCheck = 0
    /// How long the bar's frame must stay unchanged to count as resting.
    static let barRestDelay: Duration = .milliseconds(150)
    /// The covers that can be tapped to open the player, by where they are (a cell, the Continue
    /// card), with their latest global frames. Written as they scroll, read only when an open or a
    /// close starts.
    @ObservationIgnored private var sourceCovers: [ExpansionSourceID: ExpansionCover] = [:]
    /// The cover this presentation grew from, while the collapse should land on it.
    @ObservationIgnored private var source: ExpansionSourceID?
    /// An animated open from closed, waiting for the panel to be on screen at 0 (`stageDidAppear`).
    @ObservationIgnored private var pendingOpen: Int?
    /// How long a pending open waits for the panel before it settles anyway (nothing renders it:
    /// off screen, unit tests).
    static let pendingOpenFallback: Duration = .milliseconds(100)
    /// The drag in flight, if any, and the progress it started from (for `cancelInteractive`).
    @ObservationIgnored private var interaction: (id: Int, startProgress: CGFloat)?
    /// Tells whether the bar is visible (a book is loaded) when an open starts. Optional so
    /// tests and previews can omit it: then there is never a bar to grow from.
    @ObservationIgnored private let playback: PlaybackState?

    /// The settle, for taps and releases alike (spec values).
    static let animation: Animation = .spring(response: 0.35, dampingFraction: 0.86)

    /// Resigns the first responder when a presentation starts: the details screen opens in the
    /// same hierarchy as the Library search field, so a keyboard left up would cover it.
    @ObservationIgnored private let dismissKeyboard: @MainActor () -> Void

    init(playback: PlaybackState? = nil, dismissKeyboard: @escaping @MainActor () -> Void = PlayerPresentation.resignFirstResponder) {
        self.playback = playback
        self.dismissKeyboard = dismissKeyboard
    }

    static func resignFirstResponder() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Opens the details screen on `book`. `source` is the cover that was tapped (a library cell,
    /// the Continue card): the screen grows out of it and the close returns to it. Without one (the
    /// bar, a LibriVox page's Play) it grows from the bar, or the bottom strip.
    func open(_ book: AudioModel, animated: Bool, from source: ExpansionSourceID? = nil) {
        generation += 1
        interaction = nil
        pendingOpen = nil
        awaitingRestingBar = false
        landsOnMovingBar = false
        let startsPresentation = presentedBook == nil
        if startsPresentation {
            presentationID += 1
            setChapters(open: false)
            dismissKeyboard()
            self.source = source
            snapshotExpansionStart()
        }
        // Books are identified by URL, as everywhere else; the details screen is keyed by it too.
        if presentedBook == nil || presentedBook?.url != book.url {
            // Another book's chapters and text are not this one's.
            if presentedBook != nil { setChapters(open: false) }
            endReadAlongFullScreen()
            presentedBook = book
        }
        guard startsPresentation, animated, !usesPanes else {
            settleOpen(animated: animated && !usesPanes)
            return
        }
        // This change inserts the panel. A progress set in the same update would be drawn at its
        // target straight away, with nothing to animate from: the snap of #241. The panel goes on
        // screen at 0 and the spring starts once it is there.
        renderedProgress = 0
        let current = generation
        pendingOpen = current
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.pendingOpenFallback)
            guard let self, pendingOpen == current else { return }
            startPendingOpen()
        }
    }

    /// The panel is on screen (at progress 0): an open waiting for it starts its spring now.
    func stageDidAppear() {
        guard pendingOpen != nil, pendingOpen == generation else { return }
        startPendingOpen()
    }

    func close(animated: Bool) {
        generation += 1
        interaction = nil
        pendingOpen = nil
        let current = generation
        setFullyOpen(false)
        // At once, not when the collapse lands: the text would float over a closing player.
        endReadAlongFullScreen()
        if usesPanes {
            // A pane leaves at once; the browsing pane takes its room back.
            set(progress: 0, animated: false, completion: nil)
            clearBook()
            return
        }
        if retargetCollapse() { awaitingRestingBar = true }
        if awaitingRestingBar { landOnMovingBar() }
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
        if usesPanes {
            // Split, the player is a pane: a drag up on the bar opens it, and nothing is dragged.
            if presentedBook == nil, let book { open(book, animated: false) }
            return nil
        }
        generation += 1
        pendingOpen = nil
        landsOnMovingBar = false
        if presentedBook == nil {
            guard let book else { return nil }
            presentationID += 1
            dismissKeyboard()
            source = nil
            snapshotExpansionStart()
            presentedBook = book
            renderedProgress = 0
        } else if retargetCollapse() || (expansionStart == nil && playback?.loadedBook != nil) {
            // Opened with no bar (the bottom strip), and a book was loaded meanwhile (Play pressed
            // while open): the collapse lands on the real bar. Its last frame counts only if it
            // was reported at rest; otherwise wait for the bar to come back with the tab bar and
            // settle (`reportBarFrame`). A snapshot that exists is kept.
            if barFrameIsResting, barFrame != nil {
                snapshotExpansionStart()
            } else {
                awaitingRestingBar = true
            }
        }
        setFullyOpen(false)
        let current = ExpansionMath.clamp(renderedProgress)
        stop(at: current)
        let start = ExpansionMath.startFrame(bar: expansionStart, screen: screenSize)
        interaction = (generation, current)
        return InteractiveStart(
            progress: current,
            travel: ExpansionMath.travel(startFrame: start, screen: screenSize),
            id: generation
        )
    }

    /// Whether the interaction `id` is still the one in flight. A drag whose interaction ended
    /// elsewhere (a tap, a close, the scene going inactive) starts a new one on its next event.
    func isInteracting(_ id: Int) -> Bool {
        interaction?.id == id
    }

    /// Settles the drag in flight, if any, as if the finger lifted without speed: `DragGesture`
    /// calls no `onEnded` when the system cancels it (an incoming call). Called when the scene
    /// leaves `.active` and when a panel gesture resets without ending.
    func cancelInteractive() {
        guard let interaction else { return }
        let open = ExpansionMath.shouldOpen(
            progress: progress,
            velocityY: 0,
            wasOpening: progress > interaction.startProgress
        )
        endInteractive(open: open)
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
        interaction = nil
        guard presentedBook != nil else { return }
        if open {
            generation += 1
            settleOpen(animated: true)
        } else {
            close(animated: true)
        }
    }

    // MARK: - Chapters and layout

    func showResumePrompt(_ prompt: ResumePrompt) {
        resumePrompt = prompt
    }

    /// Dismisses the prompt; given an id, only if that prompt is still the one showing, so an
    /// older prompt's timer can't take down a newer one.
    func dismissResumePrompt(_ id: ResumePrompt.ID? = nil) {
        guard let prompt = resumePrompt, id == nil || prompt.id == id else { return }
        resumePrompt = nil
    }

    /// Opens or closes the chapters of the presented book. Without a presented book, or a book
    /// without chapters, they stay closed.
    func setChapters(open: Bool) {
        let value = open && !(presentedBook?.chapters.isEmpty ?? true)
        if isShowingChapters != value { isShowingChapters = value }
    }

    /// The root's split changed (a fold, a rotation, a window resize). The semantic state stays:
    /// the same book stays presented, with its chapters open or not. What is in flight settles at
    /// once, open if a book is presented, so no drag or spring is left aiming at the old layout.
    func layoutChanged(usesPanes: Bool) {
        guard self.usesPanes != usesPanes else { return }
        self.usesPanes = usesPanes
        endReadAlongFullScreen()
        generation += 1
        interaction = nil
        pendingOpen = nil
        awaitingRestingBar = false
        landsOnMovingBar = false
        guard presentedBook != nil else { return }
        stop(at: 1)
        setFullyOpen(true)
    }

    // MARK: - Reports

    /// The system can host the accessory's content more than once around placement changes, and
    /// the copy reports a frame near the top (Task 1 spike, gotcha 4): only a frame in the bottom
    /// half is the bar. Assigned only when it changes.
    func reportBarFrame(_ frame: CGRect, screenHeight: CGFloat) {
        guard frame.minY >= screenHeight / 2, frame != barFrame else { return }
        barFrame = frame
        barFrameIsResting = !isFullyOpen
        guard awaitingRestingBar, !isFullyOpen else { return }
        if landsOnMovingBar {
            origin = .bar(frame)
        } else {
            scheduleRestingSnapshot()
        }
    }

    func reportScreenSize(_ size: CGSize) {
        if screenSize != size { screenSize = size }
    }

    /// A tappable cover's global frame (a library cell's, the Continue card's), reported as it
    /// moves. Not observed: only an open or a close reads it.
    func reportSourceCover(_ cover: ExpansionCover, for id: ExpansionSourceID) {
        if sourceCovers[id] != cover { sourceCovers[id] = cover }
    }

    /// The cover left the screen (a lazy cell scrolled away, the card hidden by a search).
    func removeSourceCover(for id: ExpansionSourceID) {
        sourceCovers[id] = nil
    }

    // MARK: - Private

    private func settleOpen(animated: Bool) {
        let current = generation
        set(progress: 1, animated: animated) { [weak self] in
            guard let self, generation == current else { return }
            setFullyOpen(true)
        }
    }

    private func startPendingOpen() {
        pendingOpen = nil
        settleOpen(animated: true)
    }

    /// The bar is visible while a book is loaded and its frame was reported at rest (the screen
    /// isn't settled open when an open starts).
    private var restingBar: CGRect? {
        playback?.loadedBook != nil && barFrameIsResting ? barFrame : nil
    }

    /// The tapped cover while it is on screen, else the bar, else the bottom strip.
    private func snapshotExpansionStart() {
        let cover = source.flatMap { sourceCovers[$0] }
        let start = ExpansionMath.origin(cover: cover, bar: restingBar, screen: screenSize)
        if start.coverRadius == nil { source = nil }
        if origin != start { origin = start }
    }

    /// A collapse of a presentation that grew from a cover heads back to it, at its latest frame,
    /// while it is on screen. Once it is gone (scrolled away, deleted, the Continue card now showing
    /// another book) the collapse lands on the bar, or the strip. Returns true when it fell back
    /// to the strip with a book loaded: the bar is coming back with the tab bar, so the caller
    /// waits for it to rest (as for a presentation opened without a bar).
    private func retargetCollapse() -> Bool {
        guard let source else { return false }
        let target = ExpansionMath.origin(cover: sourceCovers[source], bar: restingBar, screen: screenSize)
        if target.coverRadius == nil { self.source = nil }
        if origin != target {
            withAnimation(.easeOut(duration: 0.25)) {
                origin = target
            }
        }
        return target == .bottomStrip && playback?.loadedBook != nil
    }

    /// Takes the bar's frame as the start once it stops changing (its insertion and the tab bar's
    /// return animate it), easing the panel's target there instead of jumping.
    private func scheduleRestingSnapshot() {
        restingCheck += 1
        let check = restingCheck
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.barRestDelay)
            guard let self, awaitingRestingBar, restingCheck == check, presentedBook != nil,
                  !isFullyOpen, let frame = barFrame else { return }
            awaitingRestingBar = false
            withAnimation(.easeOut(duration: 0.25)) {
                origin = .bar(frame)
            }
        }
    }

    /// A collapse is settling while the bar still moves: head for its latest frame now (if it was
    /// reported with the tab bar back), then follow each new one until the landing.
    private func landOnMovingBar() {
        landsOnMovingBar = true
        restingCheck += 1
        guard barFrameIsResting, let frame = barFrame, expansionStart != frame else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            origin = .bar(frame)
        }
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
        setChapters(open: false)
        endReadAlongFullScreen()
        awaitingRestingBar = false
        source = nil
        landsOnMovingBar = false
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

// MARK: - Read-along full screen

extension PlayerPresentation {
    /// The presented player's read-along text goes full screen. Without a presented player there
    /// is nothing to expand from.
    func showReadAlongFullScreen(_ fullScreen: ReadAlongFullScreen) {
        guard presentedBook != nil else { return }
        readAlongFullScreen = fullScreen
    }

    /// Back to the square (the collapse button, VoiceOver's escape, the text going away).
    func endReadAlongFullScreen() {
        if readAlongFullScreen != nil { readAlongFullScreen = nil }
    }

    /// The player screen that owns `slot` lost its text (the pill flipped back, Read-along turned
    /// off) or left: its full screen ends, and only its own.
    func endReadAlongFullScreen(of slot: ReadAlongSessionSlot) {
        if readAlongFullScreen?.slot === slot { readAlongFullScreen = nil }
    }
}

// MARK: - Chapters found in the audio

extension PlayerPresentation {
    /// The book's chapters changed (`ChapterFinder`): the presented copy takes them, and the
    /// chapters close when none are left.
    func chaptersChanged(_ chapters: [ChapterModel], ofBookAt url: URL) {
        guard presentedBook?.url == url else { return }
        presentedBook?.chapters = chapters
        if chapters.isEmpty { setChapters(open: false) }
    }

    /// The book was renamed (#322): the presented copy takes the new title.
    func titleChanged(_ title: String, ofBookAt url: URL) {
        guard presentedBook?.url == url else { return }
        presentedBook?.title = title
    }
}
