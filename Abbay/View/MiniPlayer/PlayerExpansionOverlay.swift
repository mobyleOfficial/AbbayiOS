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
    @State
    private var geometry = ExpansionGeometry()

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
    }

    private func stage(screen: CGSize, insets: EdgeInsets) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .onChange(of: screen, initial: true) {
                    presentation.reportScreenSize(screen)
                }
            if let book = presentation.presentedBook {
                ExpansionStage(
                    book: book,
                    screen: screen,
                    insets: insets,
                    geometry: geometry,
                    details: details(book, screen: screen, insets: insets)
                )
            }
        }
        .frame(width: screen.width, height: screen.height, alignment: .topLeading)
    }

    /// The details screen at full-screen size, always: the panel clips it rather than resizing it,
    /// so a drag moves it without laying it out again.
    private func details(_ book: AudioModel, screen: CGSize, insets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            // The status bar, then the grabber header (drawn above, in `ExpansionLayout`).
            Color.clear
                .frame(height: insets.top + ExpansionMetrics.headerHeight)
            PlayerView(
                book,
                state: playback,
                player: center?.player,
                downloads: downloads,
                onCoverFrame: { [geometry] in geometry.setCoverFrame($0) }
            )
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

// MARK: - Drag

/// One drag of the expansion, from the bar or from the panel: maps the vertical translation to
/// progress from where the screen was when the finger landed, and settles on release. A plain
/// class held in `@State`: writing it never re-renders the view carrying the gesture.
@MainActor
final class ExpansionDrag {
    private var start: PlayerPresentation.InteractiveStart?
    /// The translation at the first event. The gesture reports only after its minimum distance;
    /// measuring from there keeps the screen from jumping by that distance when it starts.
    private var origin: CGFloat = 0
    private var latest: CGFloat = 0

    var isActive: Bool { start != nil }

    /// `book` is the loaded book for a drag from the bar, nil for a drag on the open screen.
    func changed(translationY: CGFloat, presentation: PlayerPresentation, book: AudioModel?) {
        if start == nil {
            guard let begun = presentation.beginInteractive(book) else { return }
            start = begun
            origin = translationY
            latest = begun.progress
        }
        guard let start else { return }
        latest = ExpansionMath.progress(
            start: start.progress,
            translationY: translationY - origin,
            travel: start.travel
        )
        presentation.updateInteractive(latest)
    }

    /// Settles by the spec thresholds, read in the direction the finger moved: up from where it
    /// landed is opening, down is closing.
    func ended(velocityY: CGFloat, presentation: PlayerPresentation) {
        guard let start else { return }
        self.start = nil
        let open = ExpansionMath.shouldOpen(
            progress: latest,
            velocityY: velocityY,
            wasOpening: latest > start.progress
        )
        presentation.endInteractive(open: open)
    }
}

// MARK: - Stage

/// Reads `progress` (and the slow presentation state) and hands it to `ExpansionLayout`, which
/// SwiftUI interpolates frame by frame while the settle animates. Owns the panel's drag.
private struct ExpansionStage<Details: View>: View {
    let book: AudioModel
    let screen: CGSize
    let insets: EdgeInsets
    let geometry: ExpansionGeometry
    let details: Details

    @Environment(PlayerPresentation.self)
    private var presentation
    @State
    private var drag = ExpansionDrag()

    var body: some View {
        ExpansionLayout(
            progress: presentation.progress,
            book: book,
            screen: screen,
            insets: insets,
            start: presentation.expansionStart,
            isFullyOpen: presentation.isFullyOpen,
            geometry: geometry,
            presentation: presentation,
            drag: drag,
            details: details
        )
    }
}

// MARK: - Layout

/// The panel at one progress value. `Animatable`, so the settle re-runs this body each frame
/// with the interpolated value, which it reports back as `renderedProgress` for interruptions.
private struct ExpansionLayout<Details: View>: View, Animatable {
    var progress: CGFloat
    let book: AudioModel
    let screen: CGSize
    let insets: EdgeInsets
    let start: CGRect?
    let isFullyOpen: Bool
    let geometry: ExpansionGeometry
    let presentation: PlayerPresentation
    let drag: ExpansionDrag
    let details: Details

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }


    /// The system tab bar's accessory (iOS 26.1+) is a capsule; the hand-built dock is rounded.
    private var startsInAccessory: Bool {
        guard start != nil else { return false }
        if #available(iOS 26.1, *) { return true }
        return false
    }

    var body: some View {
        let fraction = reportRendered(progress)
        let startFrame = ExpansionMath.startFrame(bar: start, screen: screen)
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
        return ZStack(alignment: .topLeading) {
            ColorConstants.onyx.value
            Color(uiColor: CoverTint.cached(for: book))
                .opacity(barOpacity)
            // The panel's left edge moves; the details screen stays where it will land.
            details
                .environment(\.expansionDrawsPlayerCover, !isFullyOpen)
                .offset(x: -frame.minX)
                .opacity(detailsOpacity)
                // Only once settled: while moving, its off-panel parts must not take touches.
                .allowsHitTesting(isFullyOpen)
            // Only while visible: its subtitle and progress line read the clock, which must not
            // tick under the open details screen.
            if barOpacity > 0 {
                MiniPlayerFace(book: book, isAccessory: startsInAccessory)
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
                DataImageView(data: book.imageData)
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
            .onChanged { [drag, presentation] value in
                // Only the header, the cover and the moving panel carry this drag. The chapter list
                // doesn't, so it scrolls and a collapse never starts inside it.
                drag.changed(translationY: value.translation.height, presentation: presentation, book: nil)
            }
            .onEnded { [drag, presentation] value in
                drag.ended(velocityY: value.velocity.height, presentation: presentation)
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
                .accessibilityElement()
                .accessibilityLabel(Localizable.closePlayer.localized)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onClose() }
                .accessibilityIdentifier(AccessibilityID.Player.grabber)
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
                PlayButtonView(isPlaying: .constant(playback.isPlaying))
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
