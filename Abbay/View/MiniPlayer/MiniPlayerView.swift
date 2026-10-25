//
//  MiniPlayerView.swift
//  Abbay
//

import Observation
import SwiftUI
import UIKit

/// The one-row mini player: cover, title, "Chapter N · X min left", play/pause and a thin line for
/// the progress within the chapter, on a background tinted from the cover. It always shows the
/// book loaded in the player.
///
/// - Tap opens the details screen; a vertical drag expands it under the finger
///   (`PlayerExpansionOverlay`), starting from `PlayerPresentation.barFrame`; a horizontal swipe
///   goes to the next chapter (left) or back to the chapter's start (right). One `DragGesture`
///   decides the axis on its first event.
/// - Body split, so a clock tick re-renders only two leaves: this body reads `PlaybackState` alone
///   (play, pause, switch). `MiniPlayerSubtitle` and `MiniPlayerProgressLine` read `PlaybackClock`.
/// - Gesture feedback lives in `MiniPlayerSwipe`, read only by `MiniPlayerText`, and the drag's
///   own bookkeeping in `BarDrag`, a plain class: a gesture that re-renders the view carrying it can
///   stop receiving touches (Task 1 spike), so this body never reads anything a gesture writes.
///   The expansion's `progress` is read only by the overlay.
struct MiniPlayerView: View {
    @Environment(PlaybackState.self)
    private var playback
    /// Read only inside actions, never in `body`, so a tick doesn't re-render the bar.
    @Environment(PlaybackClock.self)
    private var clock
    @Environment(\.playbackCenter)
    private var center
    @Environment(PlayerPresentation.self)
    private var presentation
    @State
    private var swipe = MiniPlayerSwipe()
    @State
    private var drag = BarDrag()

    /// In the system tab bar's accessory (iOS 26.1+), which sets the height (about 48 pt) and a
    /// capsule shape; docked above the hand-built tab bar otherwise (56 pt, rounded corners).
    var isAccessory = false

    static let height: CGFloat = SpaceConstants.sx56.value
    private static let coverSide: CGFloat = SpaceConstants.sx40.value

    var body: some View {
        if let book = playback.loadedBook {
            bar(book)
        }
    }

    private func bar(_ book: AudioModel) -> some View {
        HStack(spacing: SpaceConstants.sx12.value) {
            // The bar's radius is fixed: the expansion overlay grows the cover from it.
            ArtworkView(book: book, cornerRadius: SpaceConstants.sx4.value)
                .frame(side: Self.coverSide)
                .accessibilityHidden(true)
            MiniPlayerText(
                book: book,
                swipe: swipe,
                onOpen: { open() },
                onNext: { perform(.next) },
                onRestart: { perform(.restart) }
            )
            // White both ways: the spec keeps the bar's foreground white on any cover tint, where
            // the accent's contrast isn't guaranteed.
            PlayButtonView(
                isPlaying: .constant(playback.isPlaying),
                onPlay: { play() },
                onPause: { center?.player.pause() },
                pauseColor: ColorConstants.white.value
            )
            .frame(side: SpaceConstants.sx20.value)
            .padding(SpaceConstants.sx12.value)
            .contentShape(Rectangle())
            .accessibilityIdentifier(AccessibilityID.MiniPlayer.playPause)
        }
        // In the capsule, the cover clears the rounded ends.
        .padding(.leading, isAccessory ? SpaceConstants.sx12.value : SpaceConstants.sx8.value)
        .padding(.trailing, isAccessory ? SpaceConstants.sx8.value : SpaceConstants.sx4.value)
        .frame(maxWidth: .infinity)
        .frame(height: isAccessory ? nil : Self.height)
        .frame(maxHeight: isAccessory ? .infinity : nil)
        .foregroundColor(ColorConstants.white.value)
        .modifier(CoverTintBackground(book: book))
        .overlay(alignment: .bottom) {
            // Along the capsule's flat bottom, clear of the rounded ends.
            MiniPlayerProgressLine(book: book)
                .padding(.horizontal, isAccessory ? SpaceConstants.sx20.value : 0)
        }
        .clipShape(shape)
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .gesture(barGesture)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { [presentation] frame in
            presentation.reportBarFrame(frame, screenHeight: Self.screenHeight)
        }
    }

    private var shape: AnyShape {
        isAccessory ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: SpaceConstants.sx8.value))
    }

    // MARK: - Gestures

    /// The axis is decided on the first event. Vertical drives the expansion live (through
    /// `PlayerPresentation`, which only the overlay reads); horizontal is a chapter swipe, decided
    /// on release. Global coordinates: the accessory can move while the finger is down.
    private var barGesture: some Gesture {
        DragGesture(minimumDistance: SpaceConstants.sx12.value, coordinateSpace: .global)
            .onChanged { [drag, presentation, playback] value in
                guard drag.axis(for: value.translation, startLocation: value.startLocation) == .vertical else { return }
                drag.expansion.changed(
                    translationY: value.translation.height,
                    startLocation: value.startLocation,
                    presentation: presentation,
                    book: playback.loadedBook,
                    beginsOnlyUpward: true,
                    time: value.time.timeIntervalSinceReferenceDate
                )
            }
            .onEnded { [drag, presentation] value in
                let axis = drag.axis(for: value.translation, startLocation: value.startLocation)
                drag.reset()
                if axis == .vertical {
                    drag.expansion.ended(
                        velocityY: value.velocity.height,
                        presentation: presentation,
                        time: value.time.timeIntervalSinceReferenceDate
                    )
                } else if let swipe = MiniPlayerActions.swipe(for: value.translation) {
                    perform(swipe)
                }
            }
    }

    // MARK: - Actions

    private func open() {
        guard let book = playback.loadedBook else { return }
        presentation.open(book, animated: true)
    }

    private func play() {
        guard var book = playback.loadedBook else { return }
        center?.player.play(&book)
    }

    private func perform(_ action: MiniPlayerActions.Swipe) {
        guard let book = playback.loadedBook, let player = center?.player else { return }
        let chapter = clock.currentChapter
        let didAct = switch action {
        case .next: MiniPlayerActions.nextChapter(player: player, book: book, chapter: chapter)
        case .restart: MiniPlayerActions.restartChapter(player: player, book: book, chapter: chapter)
        }
        if !didAct {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        swipe.nudge(toward: action)
    }

    /// The window's height, to tell the bar's real frame from a spurious copy near the top.
    private static var screenHeight: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen.bounds.height ?? 0
    }
}

// MARK: - Drag bookkeeping

/// Which way the bar's current drag goes, and its expansion state. Not observed: the gesture
/// writes it on every event, and nothing renders from it. The axis is decided on a gesture's
/// first event and kept for that gesture only: `DragGesture` calls no `onEnded` when the system
/// cancels it, so a new start location means a new gesture. A cancelled expansion is settled by
/// the overlay when the scene goes inactive (`PlayerPresentation.cancelInteractive`).
@MainActor
final class BarDrag {
    enum Axis {
        case vertical
        case horizontal
    }

    let expansion = ExpansionDrag()
    private var axis: Axis?
    private var startLocation: CGPoint?

    func axis(for translation: CGSize, startLocation: CGPoint) -> Axis {
        if let axis, self.startLocation == startLocation { return axis }
        let decided: Axis = ExpansionMath.isVerticalDrag(translation) ? .vertical : .horizontal
        axis = decided
        self.startLocation = startLocation
        return decided
    }

    func reset() {
        axis = nil
        startLocation = nil
    }
}

// MARK: - Swipe feedback

/// The text's horizontal nudge after a swipe. Read only by `MiniPlayerText`.
@MainActor
@Observable
final class MiniPlayerSwipe {
    private(set) var textOffset: CGFloat = 0

    private static let distance: CGFloat = SpaceConstants.sx12.value

    /// Slides the text 12 pt in the swipe's direction and back.
    func nudge(toward swipe: MiniPlayerActions.Swipe) {
        let target = swipe == .next ? -Self.distance : Self.distance
        withAnimation(.easeOut(duration: 0.12)) {
            textOffset = target
        } completion: { [weak self] in
            withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
                self?.textOffset = 0
            }
        }
    }
}

// MARK: - Leaves

/// Title and subtitle, one accessibility element (`MiniPlayer.bar`) with the bar's actions.
private struct MiniPlayerText: View {
    let book: AudioModel
    let swipe: MiniPlayerSwipe
    let onOpen: () -> Void
    let onNext: () -> Void
    let onRestart: () -> Void

    var body: some View {
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
        .offset(x: swipe.textOffset)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
        .accessibilityAction(named: Localizable.openPlayer.localized) { onOpen() }
        .accessibilityAction(named: Localizable.nextChapterAction.localized) { onNext() }
        .accessibilityAction(named: Localizable.restartChapterAction.localized) { onRestart() }
        .accessibilityIdentifier(AccessibilityID.MiniPlayer.bar)
    }
}

/// "Chapter N · X min left". Reads `PlaybackClock`. Also drawn by the expansion's bar face.
struct MiniPlayerSubtitle: View {
    let book: AudioModel

    @Environment(PlaybackClock.self)
    private var clock

    var body: some View {
        Text(MiniPlayerActions.subtitle(book: book, chapter: clock.currentChapter, bookTime: clock.bookTime))
    }
}

/// The 2 pt line along the bar's bottom edge: progress within the current chapter (or the book,
/// without chapters), white on 25% white. Reads `PlaybackClock`. Also drawn by the expansion's
/// bar face (hidden from accessibility there).
struct MiniPlayerProgressLine: View {
    let book: AudioModel

    @Environment(PlaybackClock.self)
    private var clock

    var body: some View {
        let fraction = MiniPlayerActions.progress(book: book, chapter: clock.currentChapter, bookTime: clock.bookTime)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(ColorConstants.white.value.opacity(0.25))
                Rectangle()
                    .fill(ColorConstants.white.value)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: SpaceConstants.sx2.value)
        .accessibilityElement()
        .accessibilityLabel(Localizable.chapterProgress.localized)
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier(AccessibilityID.MiniPlayer.progress)
    }
}

// MARK: - Docked bar (iOS 17.0–26.0)

/// The bar above the hand-built tab bar: shown while a book is loaded and the details screen
/// isn't settled open. Reads only `loadedBook` and `isFullyOpen`, each changing once per switch or
/// per open/close, so it never re-renders per tick or per drag frame.
struct MiniPlayerDock: View {
    @Environment(PlaybackState.self)
    private var playback
    @Environment(PlayerPresentation.self)
    private var presentation

    var body: some View {
        if playback.loadedBook != nil, !presentation.isFullyOpen {
            MiniPlayerView()
                .padding(.horizontal, SpaceConstants.sx8.value)
                .padding(.bottom, SpaceConstants.sx4.value)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Accessory (iOS 26.1+)

/// Puts the bar in the system tab bar's bottom accessory, enabled under the same condition as
/// `MiniPlayerDock`. A modifier, so the reads happen here and not in the body that builds the
/// `TabView`: a book switch or an open re-renders this, never the tabs.
@available(iOS 26.1, *)
struct MiniPlayerAccessory: ViewModifier {
    @Environment(PlaybackState.self)
    private var playback
    @Environment(PlayerPresentation.self)
    private var presentation

    func body(content: Content) -> some View {
        content
            .tabViewBottomAccessory(isEnabled: playback.loadedBook != nil && !presentation.isFullyOpen) {
                MiniPlayerView(isAccessory: true)
            }
    }
}

// MARK: - Actions

/// What the bar's gestures do, as pure functions over the player and the book.
enum MiniPlayerActions {
    enum Swipe: Equatable {
        /// Left: the next chapter.
        case next
        /// Right: the current chapter's start.
        case restart
    }

    /// How far a swipe must travel horizontally to count.
    static let swipeThreshold: CGFloat = 40

    /// Past 40 pt, and more horizontal than vertical; otherwise nil (a tap, or the vertical drag).
    static func swipe(for translation: CGSize) -> Swipe? {
        guard abs(translation.width) > swipeThreshold,
              abs(translation.width) > abs(translation.height) else { return nil }
        return translation.width < 0 ? .next : .restart
    }

    /// `false` (the bar answers with a haptic) on the last chapter or without chapters.
    static func nextChapter(player: PlayerProtocol, book: AudioModel, chapter: Int) -> Bool {
        guard book.chapters.indices.contains(chapter + 1) else { return false }
        player.skipToNextChapter()
        return true
    }

    /// Seeks to the current chapter's start, as the owner described ("return to the beginning of
    /// the chapter"); it never goes to the previous chapter. `false` without chapters.
    static func restartChapter(player: PlayerProtocol, book: AudioModel, chapter: Int) -> Bool {
        guard book.chapters.indices.contains(chapter) else { return false }
        player.seek(book.chapters[chapter].startTime)
        return true
    }

    /// "Chapter N · X min left" within the chapter; "X min left" in the book without chapters.
    static func subtitle(book: AudioModel, chapter: Int, bookTime: Double) -> String {
        guard book.chapters.indices.contains(chapter) else {
            let left = timeLeft(book.duration - bookTime)
            return Localizable.rowTimeLeft.localized(with: left.text, left.count)
        }
        let number = ChapterCountView.displayNumber(forIndex: chapter, total: book.chapters.count)
        let left = timeLeft(book.chapters[chapter].endTime - bookTime)
        return Localizable.miniPlayerSubtitle.localized(with: number, left.text, left.count)
    }

    /// 0…1 within the current chapter, or within the book without chapters.
    static func progress(book: AudioModel, chapter: Int, bookTime: Double) -> Double {
        let start: Double
        let duration: Double
        if book.chapters.indices.contains(chapter) {
            start = book.chapters[chapter].startTime
            duration = book.chapters[chapter].duration
        } else {
            start = 0
            duration = book.duration
        }
        guard duration > 0, bookTime.isFinite else { return 0 }
        return min(max((bookTime - start) / duration, 0), 1)
    }

    private static let timeLeftFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 2
        // Not `.dropLeading`, which kept a zero minute: exactly one hour read "1 h e 0 min" (#152).
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    /// Whole minutes, rounded up, so the last seconds read "1 min", never "0 min" too early.
    private static func timeLeft(_ seconds: Double) -> TimeLeftText {
        let minutes = (max(seconds, 0) / 60).rounded(.up)
        return TimeLeftText(seconds: minutes * 60, formatter: timeLeftFormatter)
    }
}
