//
//  PlayerExpansionOverlay.swift
//  Abbay
//

import Observation
import SwiftUI

/// The one presentation of the details screen: a single panel above the tabs whose frame grows
/// from the mini player's frame to the full screen as `PlayerPresentation.progress` goes 0 → 1.
///
/// - The corner radius goes from the bar's to 0; the cover grows from the bar's 40 pt to the
///   details screen's, and moves with the content.
/// - The bar's face fades out over the first 30%; the details screen fades in over the last 70%.
/// - The bar's drag up (`MiniPlayerView`) and this panel's drag down (its grabber header, its
///   cover, or anywhere on it while it's moving) write `progress` live; a release settles with
///   the spec's spring. Grabbing mid-spring continues from what is on screen.
/// - Reduce Motion: an opacity cross-fade between the same end states, no frame interpolation.
///
/// What reads what (Ruling 5, and the hard rule): this body reads only `presentedBook`, once per
/// open or close. `ExpansionStage` reads `progress`; `ExpansionLayout` gets it interpolated per
/// frame. The details screen is built here, once per book, and handed down unchanged, so neither a
/// drag frame nor a clock tick re-runs its body; only its own clock leaves tick.
struct PlayerExpansionOverlay: View {
    @Environment(PlayerPresentation.self)
    private var presentation
    @Environment(PlaybackState.self)
    private var playback
    @Environment(\.playbackCenter)
    private var center
    @Environment(\.downloadStateStore)
    private var downloads
    @Environment(\.scenePhase)
    private var scenePhase
    @State
    private var geometry = ExpansionGeometry()
    @State
    private var models = PlayerDetailsModels()

    var body: some View {
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            // The panel is laid out in screen coordinates, where the bar's global frame lives.
            GeometryReader { inner in
                stage(screen: inner.size, insets: insets)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea(.keyboard)
        .allowsHitTesting(presentation.presentedBook != nil)
        .onChange(of: scenePhase) { _, phase in
            // An incoming call cancels the gesture with no `onEnded`: settle any drag in flight,
            // including one that started on the bar (which can't watch its own gesture's reset).
            if phase != .active { presentation.cancelInteractive() }
        }
    }

    private func stage(screen: CGSize, insets: EdgeInsets) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .onChange(of: screen, initial: true) {
                    presentation.reportScreenSize(screen)
                }
            if let book = presentation.presentedBook {
                let model = models.model(
                    for: book,
                    presentationID: presentation.presentationID,
                    state: playback,
                    player: center?.player,
                    downloads: downloads
                )
                ExpansionStage(
                    book: book,
                    model: model,
                    screen: screen,
                    insets: insets,
                    geometry: geometry,
                    details: details(book, model: model, screen: screen, insets: insets)
                )
            }
        }
        .frame(width: screen.width, height: screen.height, alignment: .topLeading)
    }

    /// The details screen at full-screen size, always: the panel clips it rather than resizing it,
    /// so a drag moves it without laying it out again.
    private func details(
        _ book: AudioModel,
        model: PlayerViewModel,
        screen: CGSize,
        insets: EdgeInsets
    ) -> some View {
        VStack(spacing: 0) {
            // The status bar, then the grabber header (drawn above, in `ExpansionLayout`).
            Color.clear
                .frame(height: insets.top + ExpansionMetrics.headerHeight)
            PlayerView(model: model, onCoverFrame: { [geometry] in geometry.setCoverFrame($0) })
            .id(book.url)
        }
        .padding(.bottom, insets.bottom)
        .frame(width: screen.width, height: screen.height, alignment: .top)
        .background(ColorConstants.onyx.value)
        .coordinateSpace(.named(PlayerView.coordinateSpace))
    }
}

// MARK: - Metrics

private enum ExpansionMetrics {
    /// The grabber header above the details screen.
    static let headerHeight: CGFloat = SpaceConstants.sx44.value
    /// The bar's cover and its corner radius, where the growing cover starts.
    static let barCoverSide: CGFloat = SpaceConstants.sx40.value
    static let barCoverRadius: CGFloat = SpaceConstants.sx4.value
    /// The hand-built dock's corner radius (the accessory is a capsule).
    static let dockCornerRadius: CGFloat = SpaceConstants.sx8.value
}

// MARK: - Geometry

/// Where the details screen lays out its cover, in its own (= the screen's, when open)
/// coordinates: the growing cover's destination. Assigned only on change.
@MainActor
@Observable
final class ExpansionGeometry {
    private(set) var coverFrame: CGRect?

    func setCoverFrame(_ frame: CGRect) {
        if coverFrame != frame { coverFrame = frame }
    }
}

// MARK: - Models

/// One `PlayerViewModel` per presentation, shared by the details screen and the expansion's
/// cover and tint, so all of them follow the loaded book after a switch (Siri, CarPlay). Keyed by
/// the presentation and the book: a new presentation (even of the same book) gets a fresh model,
/// because a model that followed the loaded book once keeps following it. Built in the overlay's
/// body; the view model reads no state in `init`, so that body doesn't start depending on
/// `loadedBook`.
@MainActor
final class PlayerDetailsModels {
    private var current: PlayerViewModel?
    private var currentURL: URL?
    private var currentPresentation: Int?

    func model(
        for book: AudioModel,
        presentationID: Int,
        state: PlaybackState,
        player: PlayerProtocol?,
        downloads: DownloadStateStore?
    ) -> PlayerViewModel {
        if let current, currentURL == book.url, currentPresentation == presentationID { return current }
        let model = PlayerViewModel(book, state: state, player: player, downloads: downloads)
        current = model
        currentURL = book.url
        currentPresentation = presentationID
        return model
    }
}

// MARK: - Drag

/// One drag of the expansion, from the bar, the panel or the chapter list: maps the vertical
/// translation to progress from where the screen was when the finger landed, and settles on
/// release. A plain class held in `@State`: writing it never re-renders the view carrying the
/// gesture.
///
/// `DragGesture` calls no `onEnded` when the system cancels a gesture, so a drag never trusts
/// its leftovers: an event with another start location is a new gesture, and an interaction the
/// presentation ended elsewhere is over. Either way the next event begins a new interaction.
@MainActor
final class ExpansionDrag {
    private var start: PlayerPresentation.InteractiveStart?
    private var startLocation: CGPoint?
    /// The translation at the first event. The gesture reports only after its minimum distance;
    /// measuring from there keeps the screen from jumping by that distance when it starts.
    private var origin: CGFloat = 0
    private var latest: CGFloat = 0
    /// Recent (time, translation) samples, for `ExpansionMath.releaseVelocity`.
    private var samples: [(time: TimeInterval, translationY: CGFloat)] = []

    var isActive: Bool { start != nil }

    /// `book` is the loaded book for a drag from the bar, nil for a drag on the open screen.
    /// `beginsOnlyUpward` (the bar): begin only once the finger is above where it landed, so a
    /// downward drag on the bar presents nothing (no details screen built, no overlay taking
    /// touches for a settle, no invisible full-screen panel under Reduce Motion).
    func changed(
        translationY: CGFloat,
        startLocation: CGPoint,
        presentation: PlayerPresentation,
        book: AudioModel?,
        beginsOnlyUpward: Bool = false,
        time: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        if let current = start,
           self.startLocation != startLocation || !presentation.isInteracting(current.id) {
            start = nil
        }
        if start == nil {
            if beginsOnlyUpward, translationY >= 0 { return }
            guard let begun = presentation.beginInteractive(book) else { return }
            start = begun
            self.startLocation = startLocation
            origin = translationY
            latest = begun.progress
            samples.removeAll(keepingCapacity: true)
        }
        guard let start else { return }
        samples.append((time, translationY))
        if samples.count > 12 { samples.removeFirst(samples.count - 12) }
        latest = ExpansionMath.progress(
            start: start.progress,
            translationY: translationY - origin,
            travel: start.travel
        )
        presentation.updateInteractive(latest)
    }

    /// Settles by the spec thresholds, read in the direction the finger moved: up from where it
    /// landed is opening, down is closing; a flick decides by its own direction. `time` is the lift (`DragGesture.Value.time`), so a
    /// finger held still before lifting reads as slow.
    func ended(
        velocityY: CGFloat,
        presentation: PlayerPresentation,
        time: TimeInterval? = nil
    ) {
        let velocity = ExpansionMath.releaseVelocity(reported: velocityY, samples: samples, releaseTime: time)
        guard let start = finish(presentation) else { return }
        let open = ExpansionMath.shouldOpen(
            progress: latest,
            velocityY: velocity,
            wasOpening: latest > start.progress
        )
        presentation.endInteractive(open: open)
    }

    /// The gesture reset without ending (the system cancelled it): settle as a release with no
    /// speed.
    func cancel(presentation: PlayerPresentation) {
        guard let start = finish(presentation) else { return }
        let open = ExpansionMath.shouldOpen(progress: latest, velocityY: 0, wasOpening: latest > start.progress)
        presentation.endInteractive(open: open)
    }

    /// Clears this drag; returns its start if its interaction is still the one in flight.
    private func finish(_ presentation: PlayerPresentation) -> PlayerPresentation.InteractiveStart? {
        defer {
            start = nil
            startLocation = nil
            samples.removeAll(keepingCapacity: true)
        }
        guard let start, presentation.isInteracting(start.id) else { return nil }
        return start
    }
}

// MARK: - Collapse from the chapter list

/// The chapter list's collapse (iOS 18+, where `onScrollGeometryChange` tells where the list
/// is): a downward drag that starts while the list rests at its top collapses the screen, and the
/// list stops scrolling for that gesture. Any other drag scrolls the list. Decided once per
/// gesture, on its first event. On iOS 17 the list carries none of this: the header and the cover
/// are the only collapse handles there.
@MainActor
@Observable
final class ExpansionListCollapse {
    /// True while a gesture collapses the screen; the list disables its scrolling meanwhile.
    private(set) var isEngaged = false
    /// The list's offset from its top resting position, reported by the list. Not observed.
    @ObservationIgnored var listOffset: CGFloat = 0
    @ObservationIgnored private let presentation: PlayerPresentation
    @ObservationIgnored private let drag = ExpansionDrag()
    @ObservationIgnored private var decidedFor: CGPoint?

    init(presentation: PlayerPresentation) {
        self.presentation = presentation
    }

    func changed(
        translation: CGSize,
        startLocation: CGPoint,
        time: TimeInterval = Date.timeIntervalSinceReferenceDate
    ) {
        if decidedFor != startLocation {
            decidedFor = startLocation
            let engage = presentation.isFullyOpen
                && translation.height > 0
                && ExpansionMath.isVerticalDrag(translation)
                && ExpansionMath.canStartCollapse(listOffset: listOffset, fromHeader: false)
            setEngaged(engage)
        }
        guard isEngaged else { return }
        drag.changed(
            translationY: translation.height,
            startLocation: startLocation,
            presentation: presentation,
            book: nil,
            time: time
        )
    }

    func ended(velocityY: CGFloat, time: TimeInterval? = nil) {
        if isEngaged { drag.ended(velocityY: velocityY, presentation: presentation, time: time) }
        reset()
    }

    /// The gesture reset without ending.
    func cancel() {
        if isEngaged { drag.cancel(presentation: presentation) }
        reset()
    }

    private func reset() {
        decidedFor = nil
        setEngaged(false)
    }

    private func setEngaged(_ value: Bool) {
        if isEngaged != value { isEngaged = value }
    }
}

/// Attaches the list collapse to the details screen's chapter `List` on iOS 18+; nothing on
/// iOS 17 or without a handler (the LibriVox page's list).
struct ListCollapseModifier: ViewModifier {
    let handler: ExpansionListCollapse?

    @GestureState
    private var isDragging = false

    func body(content: Content) -> some View {
        if #available(iOS 18, *), let handler {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, offset in
                    handler.listOffset = offset
                }
                .scrollDisabled(handler.isEngaged)
                .simultaneousGesture(
                    DragGesture(minimumDistance: SpaceConstants.sx8.value, coordinateSpace: .global)
                        .updating($isDragging) { _, state, _ in state = true }
                        .onChanged { value in
                            handler.changed(
                                translation: value.translation,
                                startLocation: value.startLocation,
                                time: value.time.timeIntervalSinceReferenceDate
                            )
                        }
                        .onEnded { value in
                            handler.ended(
                                velocityY: value.velocity.height,
                                time: value.time.timeIntervalSinceReferenceDate
                            )
                        }
                )
                .onChange(of: isDragging) { _, dragging in
                    guard !dragging else { return }
                    // After a normal end `onEnded` has run (or runs next): only a reset with no
                    // end finds the gesture still engaged.
                    DispatchQueue.main.async { handler.cancel() }
                }
        } else {
            content
        }
    }
}

private struct ExpansionListCollapseKey: EnvironmentKey {
    static let defaultValue: ExpansionListCollapse? = nil
}

extension EnvironmentValues {
    /// Set on the details screen by the expansion; read by its chapter list.
    var expansionListCollapse: ExpansionListCollapse? {
        get { self[ExpansionListCollapseKey.self] }
        set { self[ExpansionListCollapseKey.self] = newValue }
    }
}

// MARK: - Stage

/// Reads `progress` (and the slow presentation state) and hands it to `ExpansionLayout`, which
/// SwiftUI interpolates frame by frame while the settle animates. Owns the panel's drag.
private struct ExpansionStage<Details: View>: View {
    let book: AudioModel
    let model: PlayerViewModel
    let screen: CGSize
    let insets: EdgeInsets
    let geometry: ExpansionGeometry
    let details: Details

    @Environment(PlayerPresentation.self)
    private var presentation
    @State
    private var drag = ExpansionDrag()
    /// Built once per stage (the presentation is the app's one instance).
    @State
    private var listCollapse: ExpansionListCollapse?

    var body: some View {
        ExpansionLayout(
            progress: presentation.progress,
            book: book,
            model: model,
            screen: screen,
            insets: insets,
            startFrame: ExpansionMath.startFrame(bar: presentation.expansionStart, screen: screen),
            startsFromBar: presentation.expansionStart != nil,
            isFullyOpen: presentation.isFullyOpen,
            geometry: geometry,
            presentation: presentation,
            drag: drag,
            listCollapse: listCollapse,
            details: details
        )
        .onAppear {
            if listCollapse == nil { listCollapse = ExpansionListCollapse(presentation: presentation) }
        }
    }
}

// MARK: - Layout

/// The panel at one progress value. `Animatable`, so the settle re-runs this body each frame
/// with the interpolated value, which it reports back as `renderedProgress` for interruptions.
private struct ExpansionLayout<Details: View>: View, Animatable {
    var progress: CGFloat
    let book: AudioModel
    let model: PlayerViewModel
    let screen: CGSize
    let insets: EdgeInsets
    /// Animatable too: a start taken late (the bar coming back to rest) eases in.
    var startFrame: CGRect
    let startsFromBar: Bool
    let isFullyOpen: Bool
    let geometry: ExpansionGeometry
    let presentation: PlayerPresentation
    let drag: ExpansionDrag
    let listCollapse: ExpansionListCollapse?
    let details: Details

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    /// Resets when the panel's drag ends or is cancelled; a reset with no `onEnded` settles.
    @GestureState
    private var isPanelDragging = false

    var animatableData: AnimatablePair<CGFloat, CGRect.AnimatableData> {
        get { AnimatablePair(progress, startFrame.animatableData) }
        set {
            progress = newValue.first
            startFrame.animatableData = newValue.second
        }
    }


    /// The system tab bar's accessory (iOS 26.1+) is a capsule; the hand-built dock is rounded.
    private var startsInAccessory: Bool {
        guard startsFromBar else { return false }
        if #available(iOS 26.1, *) { return true }
        return false
    }

    var body: some View {
        let fraction = reportRendered(progress)
        let full = CGRect(origin: .zero, size: screen)
        let frame = reduceMotion ? full : ExpansionMath.interpolate(startFrame, full, fraction)
        let startRadius = startsInAccessory ? startFrame.height / 2 : ExpansionMetrics.dockCornerRadius
        let corner = reduceMotion ? 0 : ExpansionMath.cornerRadius(from: startRadius, progress: fraction)
        // With Reduce Motion the whole panel cross-fades instead.
        let fade = reduceMotion ? fraction : 1

        ZStack(alignment: .topLeading) {
            panel(frame: frame, startFrame: startFrame, corner: corner, fraction: fraction)
                .opacity(fade)
            cover(frame: frame, startFrame: startFrame, fraction: fraction)
                .opacity(fade)
        }
        .frame(width: screen.width, height: screen.height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { presentation.close(animated: true) }
        .onChange(of: isPanelDragging) { _, dragging in
            guard !dragging else { return }
            // After a normal end `onEnded` has run (or runs next) and cleared the drag; only a
            // gesture the system cancelled leaves it active.
            DispatchQueue.main.async { [drag, presentation] in
                if drag.isActive { drag.cancel(presentation: presentation) }
            }
        }
    }

    /// Tells the presentation what is on screen, for a grab mid-spring; returns it clamped.
    private func reportRendered(_ value: CGFloat) -> CGFloat {
        presentation.renderedProgress = value
        return ExpansionMath.clamp(value)
    }

    // MARK: Panel

    private func panel(frame: CGRect, startFrame: CGRect, corner: CGFloat, fraction: CGFloat) -> some View {
        let barOpacity = reduceMotion ? 0 : ExpansionMath.barContentOpacity(fraction)
        let detailsOpacity = reduceMotion ? 1 : ExpansionMath.detailsOpacity(fraction)
        // The book the details screen shows: after a switch while open, the loaded one.
        let art = model.book
        let isCollapsingFromList = listCollapse?.isEngaged ?? false
        return ZStack(alignment: .topLeading) {
            ColorConstants.onyx.value
            Color.clear
                .modifier(CoverTintBackground(book: art))
                .opacity(barOpacity)
            // The panel's left edge moves; the details screen stays where it will land.
            details
                .environment(\.expansionDrawsPlayerCover, !isFullyOpen)
                .environment(\.expansionListCollapse, listCollapse)
                .offset(x: -frame.minX)
                .opacity(detailsOpacity)
                // Only once settled: while moving, its off-panel parts must not take touches.
                // A collapse dragged from the chapter list keeps it, so that gesture survives.
                .allowsHitTesting(isFullyOpen || isCollapsingFromList)
            // Only while visible: its subtitle and progress line read the clock, which must not
            // tick under the open details screen.
            if barOpacity > 0 {
                MiniPlayerFace(book: art, isAccessory: startsInAccessory)
                    .frame(width: startFrame.width, height: startFrame.height)
                    .offset(x: startFrame.minX - frame.minX)
                    .opacity(barOpacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if !isFullyOpen {
                // While it moves, the whole panel is a handle: a grab mid-spring continues from
                // there, and a tap (on what looks like the bar, as it lands) opens it.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { presentation.open(book, animated: true) }
                    .gesture(panelDrag)
                    .accessibilityHidden(true)
            }
            ExpansionHeader(drag: panelDrag) {
                presentation.close(animated: true)
            }
            .padding(.top, insets.top)
            .frame(width: screen.width)
            .offset(x: -frame.minX)
            .opacity(detailsOpacity)
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .offset(x: frame.minX, y: frame.minY)
    }

    // MARK: Cover

    /// The cover, drawn here while the panel moves so it can grow from the bar's 40 pt. Settled
    /// open, the details screen draws its own (which follows a book switch), and this stays as
    /// a transparent handle over it.
    private func cover(frame: CGRect, startFrame: CGRect, fraction: CGFloat) -> some View {
        let target = geometry.coverFrame ?? defaultCoverFrame
        let art = model.book
        let side = ExpansionMetrics.barCoverSide
        let leading = startsInAccessory ? SpaceConstants.sx12.value : SpaceConstants.sx8.value
        // Interpolated in the panel's own coordinates, so the cover rides with the panel's top edge
        // (like the bar's face and the details screen) instead of lagging at the bottom: from the
        // bar's cover slot to where the details screen lays it out (its x is the screen's).
        let fromSlot = CGRect(x: leading, y: (startFrame.height - side) / 2, width: side, height: side)
        let toSlot = target.offsetBy(dx: -frame.minX, dy: 0)
        let inPanel = ExpansionMath.interpolate(fromSlot, toSlot, fraction)
        let rect = reduceMotion ? target : inPanel.offsetBy(dx: frame.minX, dy: frame.minY)
        let radius = reduceMotion
            ? PlayerView.coverRadius
            : ExpansionMath.lerp(ExpansionMetrics.barCoverRadius, PlayerView.coverRadius, fraction)
        return ZStack {
            if !isFullyOpen {
                DataImageView(data: art.imageData)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: radius))
            }
            Color.clear
                .contentShape(Rectangle())
                .gesture(panelDrag)
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .accessibilityHidden(true)
    }

    /// Before the details screen has reported its cover: centered under the header.
    private var defaultCoverFrame: CGRect {
        let side = PlayerView.coverSide
        return CGRect(
            x: (screen.width - side) / 2,
            y: insets.top + ExpansionMetrics.headerHeight,
            width: side,
            height: side
        )
    }

    // MARK: Gesture

    /// The panel's drag: from the grabber header or the cover when open, from anywhere while it
    /// moves. Global coordinates, because the panel moves under the finger.
    private var panelDrag: some Gesture {
        DragGesture(minimumDistance: SpaceConstants.sx8.value, coordinateSpace: .global)
            .updating($isPanelDragging) { _, state, _ in state = true }
            .onChanged { [drag, presentation] value in
                // The header, the cover and the moving panel carry this drag; the chapter list has
                // its own (`ExpansionListCollapse`, iOS 18+).
                drag.changed(
                    translationY: value.translation.height,
                    startLocation: value.startLocation,
                    presentation: presentation,
                    book: nil,
                    time: value.time.timeIntervalSinceReferenceDate
                )
            }
            .onEnded { [drag, presentation] value in
                drag.ended(
                    velocityY: value.velocity.height,
                    presentation: presentation,
                    time: value.time.timeIntervalSinceReferenceDate
                )
            }
    }
}

// MARK: - Header

/// The details screen's top: the grabber (the collapse handle, which replaces the old sheet
/// grabber) and the close chevron. Both carry the collapse drag.
private struct ExpansionHeader<Drag: Gesture>: View {
    let drag: Drag
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Capsule()
                .fill(ColorConstants.spanishGray.value)
                .frame(width: SpaceConstants.sx36.value, height: 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(drag)
                // The chevron is VoiceOver's one "Close player" (with the escape action); the
                // grabber is a drag handle only. The identifier stays for the UI tests' drags.
                .accessibilityIdentifier(AccessibilityID.Player.grabber)
                .accessibilityHidden(true)
            HStack {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .frame(side: SpaceConstants.sx44.value)
                        .contentShape(Rectangle())
                }
                .foregroundColor(ColorConstants.white.value)
                .accessibilityLabel(Localizable.closePlayer.localized)
                .accessibilityIdentifier(AccessibilityID.Player.close)
                // A drag that starts on the button still collapses.
                .simultaneousGesture(drag)
                Spacer()
            }
            .padding(.horizontal, SpaceConstants.sx16.value)
        }
        .frame(height: ExpansionMetrics.headerHeight)
    }
}

// MARK: - Bar face

/// What the bar looks like, drawn inside the panel while it is small and fading out by 30%, so
/// the expansion starts as the bar itself. The cover is drawn by the layout (it grows). Only for
/// the loaded book: another book grows from the bar's frame without its face.
private struct MiniPlayerFace: View {
    let book: AudioModel
    let isAccessory: Bool

    @Environment(PlaybackState.self)
    private var playback

    var body: some View {
        if playback.loadedBook?.url == book.url {
            HStack(spacing: SpaceConstants.sx12.value) {
                Color.clear
                    .frame(side: SpaceConstants.sx40.value)
                VStack(alignment: .leading, spacing: SpaceConstants.sx2.value) {
                    Text(book.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    MiniPlayerSubtitle(book: book)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .opacity(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PlayButtonView(isPlaying: .constant(playback.isPlaying), pauseColor: ColorConstants.white.value)
                    .frame(side: SpaceConstants.sx20.value)
                    .padding(SpaceConstants.sx12.value)
            }
            .padding(.leading, isAccessory ? SpaceConstants.sx12.value : SpaceConstants.sx8.value)
            .padding(.trailing, isAccessory ? SpaceConstants.sx8.value : SpaceConstants.sx4.value)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundColor(ColorConstants.white.value)
            .overlay(alignment: .bottom) {
                MiniPlayerProgressLine(book: book)
                    .padding(.horizontal, isAccessory ? SpaceConstants.sx20.value : 0)
            }
        }
    }
}

// MARK: - Cover hand-off

private struct ExpansionDrawsPlayerCoverKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the expansion draws the details screen's cover itself (it grows from the bar):
    /// `PlayerView` keeps the cover's space but hides its image.
    var expansionDrawsPlayerCover: Bool {
        get { self[ExpansionDrawsPlayerCoverKey.self] }
        set { self[ExpansionDrawsPlayerCoverKey.self] = newValue }
    }
}

// MARK: - Tab bar

/// Hides the system tab bar (iOS 26.1+) once the details screen has settled open, and shows it
/// again as soon as a close or a drag starts (Ruling 6: never mid-drag, where hiding it would move
/// the accessory under the finger). On the hand-built tabs it does nothing; `RootTabs` hides its
/// own bar with `HiddenWhilePlayerIsOpen`. Reads only `isFullyOpen`.
struct TabBarHiddenWhilePlayerIsOpen: ViewModifier {
    @Environment(PlayerPresentation.self)
    private var presentation

    func body(content: Content) -> some View {
        content
            .toolbar(presentation.isFullyOpen ? .hidden : .automatic, for: .tabBar)
    }
}

/// Removes the hand-built tab bar while the details screen is settled open, under the same rule.
struct HiddenWhilePlayerIsOpen: ViewModifier {
    @Environment(PlayerPresentation.self)
    private var presentation

    func body(content: Content) -> some View {
        if !presentation.isFullyOpen {
            content
        }
    }
}
