//
//  PlayerView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 10/07/23.
//

import SwiftUI

/// The details screen, "Player A" of the Liquid Glass redesign (#166 G1): a large cover, a
/// left-aligned title block, the scrubber, the transport and two glass pills (speed, chapters).
/// It is drawn inside the expansion overlay (`PlayerExpansionOverlay`), which paints the cover-tint
/// gradient behind it and adds the header (glass close button, grabber) on top.
///
/// The Chapters pill opens the chapter list as a glass panel floating over the cover (G2,
/// `ChaptersPanel`); nothing else on the screen moves.
///
/// What it reads, so a clock tick does as little as possible:
/// - this body reads the slow state only (the book, playing or not, via `PlayerViewModel`);
/// - `PlayerTimeline` reads `PlaybackClock.bookTime` and re-renders once per tick;
/// - `PlayerSubtitle` reads `PlaybackClock.currentChapter`, so it re-renders per chapter;
/// - the open panel reads the clock too, but redraws its rows only when what they show changes.
struct PlayerView: View {
    // MARK: - Properties
    /// Shared with the expansion, which draws the growing cover and tint from the same book.
    private let model: PlayerViewModel
    /// The expansion draws the cover itself while it grows from the bar, landing exactly where
    /// this view lays it out; meanwhile the space stays and only the image is hidden.
    @Environment(\.expansionDrawsPlayerCover)
    private var hidesCover
    /// Where the cover is laid out, in `coordinateSpace`: the growing cover's destination.
    private let onCoverFrame: ((CGRect) -> Void)?
    /// Told when the chapter panel opens or closes: the expansion's cover handle sits above this
    /// screen, under the panel, and stands aside while it is open.
    private let onChaptersOpen: ((Bool) -> Void)?
    /// Skip amounts and speeds. Changes only from Settings or the speed sheet, never on a tick.
    @Environment(AppSettings.self)
    private var settings
    @ReduceMotion
    private var reduceMotion
    @State
    private var isShowingSpeed = false
    /// Whether the chapters are open: shared state (`PlayerPresentation.isShowingChapters`), so a
    /// fold or a resize keeps them open in the other form.
    @Environment(PlayerPresentation.self)
    private var presentation
    /// Split (#255), the chapters are a pane in browsing's place (`ChaptersPane`) and this screen
    /// draws no panel over itself.
    @Environment(\.paneLayout)
    private var paneLayout
    private var isShowingChapters: Bool { presentation.isShowingChapters }
    /// The panel's binding to the shared state.
    private var chaptersBinding: Binding<Bool> {
        Binding(
            get: { [presentation] in presentation.isShowingChapters },
            set: { [presentation] in presentation.setChapters(open: $0) }
        )
    }
    /// The pills' row, in `Self.layoutSpace`: the chapter panel sits just above it.
    @State
    private var pillsFrame: CGRect = .zero
    /// A chapter row's height and the panel's handle and header, estimated at the current text
    /// size, so a short book's panel fits its rows instead of showing empty glass.
    @ScaledMetric(relativeTo: .subheadline)
    private var panelRowHeight: CGFloat = 58
    @ScaledMetric(relativeTo: .headline)
    private var panelChromeHeight: CGFloat = 92
    private static let dimReach: CGFloat = 200

    /// The named space `onCoverFrame` reports in: the details screen's own frame.
    static let coordinateSpace = "player.details"
    /// This view's own space, where the chapter panel is placed.
    private static let layoutSpace = "player.view"
    /// The cover's largest side. It fills the width minus the margins, and shrinks on a short
    /// screen so the transport and the pills keep their room.
    static let coverSide: CGFloat = SpaceConstants.sx72.value * SpaceConstants.sx4.value + SpaceConstants.sx72.value
    /// The chapter panel's least height: its header and three rows and a bit, so the list can be
    /// read and scrolled on a short screen (the iPhone SE, the iOS 27.1 iPhone Duo; #203).
    static let minChapterListHeight: CGFloat = SpaceConstants.sx56.value * SpaceConstants.sx4.value
    /// The spec's ~14 pt. The expansion's growing cover lands on the same radius.
    static let coverRadius: CGFloat = 14
    private static let margin = SpaceConstants.sx24.value

    // MARK: - Inits
    init(
        model: PlayerViewModel,
        onCoverFrame: ((CGRect) -> Void)? = nil,
        onChaptersOpen: ((Bool) -> Void)? = nil
    ) {
        self.model = model
        self.onCoverFrame = onCoverFrame
        self.onChaptersOpen = onChaptersOpen
    }

    // MARK: - Body
    var body: some View {
        AbbayGlassContainer {
            VStack(spacing: SpaceConstants.sx16.value) {
                // The cover is offered space first, but only what is left once the rest has its
                // own: it shrinks (staying square) on a short screen.
                coverView
                    .layoutPriority(1)
                titleBlock
                VStack(spacing: SpaceConstants.sx8.value) {
                    PlayerTimeline(model: model)
                    PlayerDownloadLine(model: model)
                }
                playerButtonsView
                pills
            }
            .padding(.horizontal, Self.margin)
            .padding(.top, SpaceConstants.sx8.value)
            .padding(.bottom, SpaceConstants.sx12.value)
            .overlay { chaptersOverlay }
            .onChange(of: showsPanel) { _, open in
                onChaptersOpen?(open)
            }
            .onAppear { onChaptersOpen?(showsPanel) }
            .onDisappear { onChaptersOpen?(false) }
            .coordinateSpace(.named(Self.layoutSpace))
        }
    }

    // MARK: - Cover view
    private var coverView: some View {
        ArtworkView(book: model.book, cornerRadius: Self.coverRadius, shadow: true)
            // A square as wide as the screen allows, smaller when the height runs short.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .opacity(hidesCover ? 0 : 1)
            // Measured on the square that is drawn, not on the `coverSide` frame around it: when
            // the height runs short, that frame is wider than the square, and the expansion's cover
            // grew into it and then snapped down to the real cover as it settled (#254).
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(Self.coordinateSpace))
            } action: { frame in
                onCoverFrame?(frame)
            }
            .frame(maxWidth: Self.coverSide, maxHeight: Self.coverSide)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    // MARK: - Title
    /// Left-aligned: the title in white (it no longer turns green while playing), then the author
    /// and "Ch N of M".
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: SpaceConstants.sx2.value) {
            Text(model.book.title)
                .font(.title3.bold())
                .foregroundColor(ColorConstants.white.value)
                .lineLimit(2)
                .accessibilityIdentifier(AccessibilityID.Player.title)
            PlayerSubtitle(model: model)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Player buttons
    /// Back, play/pause, forward. The skips jump by the Settings amounts, and their SF Symbols
    /// draw that number. Play/pause is the dominant control.
    private var playerButtonsView: some View {
        let back = settings.skipBackward
        let forward = settings.skipForward
        return HStack(spacing: SpaceConstants.sx48.value) {
            IconButtonView(systemName: back.backwardSymbol) {
                model.backward(withSeconds: back.seconds)
            }
            .frame(side: SpaceConstants.sx32.value)
            .accessibilityLabel(Localizable.skipBackAction.localized(with: back.rawValue))
            .accessibilityIdentifier(AccessibilityID.Player.transport(AccessibilityID.Transport.back))
            PlayButtonView(
                isPlaying: .constant(model.isPlaying),
                onPlay: { model.play() },
                onPause: { model.pause() },
                pauseColor: ColorConstants.white.value
            )
            .frame(side: SpaceConstants.sx44.value)
            .accessibilityIdentifier(AccessibilityID.Player.transport(AccessibilityID.Transport.play))
            IconButtonView(systemName: forward.forwardSymbol) {
                model.forward(withSeconds: forward.seconds)
            }
            .frame(side: SpaceConstants.sx32.value)
            .accessibilityLabel(Localizable.skipForwardAction.localized(with: forward.rawValue))
            .accessibilityIdentifier(AccessibilityID.Player.transport(AccessibilityID.Transport.forward))
        }
        .frame(height: SpaceConstants.sx56.value)
        .foregroundColor(ColorConstants.white.value)
    }

    // MARK: - Pills
    /// Speed on the left, Chapters on the right. A book with no chapters has no Chapters pill.
    private var pills: some View {
        HStack {
            speedPill
            Spacer()
            if !model.book.chapters.isEmpty {
                chaptersPill
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(Self.layoutSpace))
        } action: { frame in
            pillsFrame = frame
        }
    }

    private var speedPill: some View {
        let speed = model.speed(in: settings)
        return Button {
            isShowingSpeed = true
        } label: {
            PlayerPill(text: PlaybackSpeed.label(speed))
                .monospacedDigit()
        }
        .buttonStyle(.plain)
        .foregroundColor(speed == PlaybackSpeed.normal ? ColorConstants.white.value : ColorConstants.malachite.value)
        .accessibilityLabel(Localizable.playbackSpeed.localized)
        .accessibilityValue(PlaybackSpeed.label(speed))
        .accessibilityIdentifier(AccessibilityID.Player.speed)
        .sheet(isPresented: $isShowingSpeed) {
            SpeedSheetView(
                speed: model.speed(in: settings),
                defaultSpeed: settings.defaultSpeed,
                onChange: { model.setSpeed($0, in: settings) },
                onSetDefault: { settings.defaultSpeed = $0 }
            )
        }
    }

    /// "☰ Chapters", or "✕ Chapters" while the panel is open; a tap toggles it.
    private var chaptersPill: some View {
        Button {
            setChapters(open: !isShowingChapters)
        } label: {
            PlayerPill(
                text: Localizable.chaptersTitle.localized,
                systemImage: isShowingChapters ? "xmark" : "list.bullet"
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(ColorConstants.white.value)
        .accessibilityLabel(
            isShowingChapters ? Localizable.closeChapters.localized : Localizable.chaptersTitle.localized
        )
        .accessibilityIdentifier(AccessibilityID.Player.chapters)
    }

    // MARK: - Chapters panel (G2)

    /// The compact panel is up: the chapters are open and the window is one pane.
    private var showsPanel: Bool {
        isShowingChapters && !paneLayout.isSplit
    }

    @ViewBuilder
    private var chaptersOverlay: some View {
        if showsPanel {
            GeometryReader { proxy in
                let frame = ChaptersPanelLayout.frame(
                    container: proxy.size,
                    pillsTop: pillsFrame.minY,
                    idealHeight: ChaptersPanelLayout.idealHeight(
                        chapterCount: model.book.chapters.count,
                        rowHeight: panelRowHeight,
                        chromeHeight: panelChromeHeight
                    )
                )
                ZStack(alignment: .topLeading) {
                    // The faint dim behind the panel; a tap outside the panel closes it.
                    Color.black.opacity(0.18)
                        // Up under the header too (drawn above this screen), so the dim has no edge.
                        .padding(.top, -Self.dimReach)
                        .contentShape(Rectangle())
                        .onTapGesture { setChapters(open: false) }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                    ChaptersPanel(
                        model: model,
                        isPresented: chaptersBinding,
                        closeAnimation: panelAnimation
                    )
                    .frame(width: frame.width, height: frame.height)
                    // Laid out there (not offset), so its SwiftUI gestures hit-test where it draws.
                    .padding(.leading, frame.minX)
                    .padding(.top, frame.minY)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(panelTransition)
                }
            }
        }
    }

    /// Grows from the Chapters pill (the panel's bottom-right corner) and fades; with Reduce
    /// Motion it only fades.
    private var panelTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.2, anchor: .bottomTrailing).combined(with: .opacity)
    }

    private var panelAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.82)
    }

    private func setChapters(open: Bool) {
        guard isShowingChapters != open else { return }
        withAnimation(panelAnimation) {
            presentation.setChapters(open: open)
        }
    }
}

// MARK: - Panel layout

/// Where the chapter panel sits, in the details screen's own coordinates: anchored bottom-right,
/// just above the pills, spanning most of the width, as tall as about eight rows when the screen
/// allows. Pure, so it is unit tested.
enum ChaptersPanelLayout {
    /// About eight rows and the header at the default text size: the most the panel asks for.
    static let maxHeight: CGFloat = 440
    /// The gap between the panel and the pills, and the panel's least distance from the top.
    static let gap: CGFloat = SpaceConstants.sx12.value
    static let leadingInset: CGFloat = SpaceConstants.sx40.value
    static let trailingInset: CGFloat = SpaceConstants.sx16.value

    /// Tall enough for the book's rows (estimated), up to `maxHeight`; the list scrolls past that.
    static func idealHeight(chapterCount: Int, rowHeight: CGFloat, chromeHeight: CGFloat) -> CGFloat {
        min(maxHeight, chromeHeight + CGFloat(max(chapterCount, 1)) * rowHeight)
    }

    static func frame(container: CGSize, pillsTop: CGFloat, idealHeight: CGFloat) -> CGRect {
        // Before the pills report (the first layout pass), assume they sit at the bottom.
        let top = pillsTop > 0 ? pillsTop : container.height
        let bottom = max(top - gap, 0)
        let available = max(bottom - gap, 0)
        let height = min(idealHeight, available)
        let width = max(container.width - leadingInset - trailingInset, 0)
        return CGRect(x: leadingInset, y: bottom - height, width: width, height: height)
    }
}

// MARK: - Leaves

/// A glass capsule with a label, the look of the speed and chapters pills.
private struct PlayerPill: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: SpaceConstants.sx4.value) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, SpaceConstants.sx16.value)
        .padding(.vertical, SpaceConstants.sx8.value + SpaceConstants.sx2.value)
        .abbayGlass(in: Capsule(), interactive: true)
        .contentShape(Capsule())
    }
}

/// "Author · Ch N of M", or just the author for a book without chapters. Reads
/// `PlaybackClock.currentChapter` only.
struct PlayerSubtitle: View {
    let model: PlayerViewModel

    @Environment(PlaybackClock.self)
    private var clock

    var body: some View {
        let book = model.book
        let text = Self.text(
            author: book.artist,
            chapter: model.currentChapter(in: clock),
            chapterCount: book.chapters.count
        )
        if !text.isEmpty {
            Text(text)
                .font(.subheadline)
                .foregroundColor(ColorConstants.white.value.opacity(0.6))
                .lineLimit(1)
        }
    }

    static func text(author: String, chapter: Int, chapterCount: Int) -> String {
        var parts: [String] = []
        if !author.isEmpty { parts.append(author) }
        if chapterCount > 0 {
            let number = min(max(chapter, 0), chapterCount - 1) + 1
            parts.append(Localizable.chapterPosition.localized(with: number, chapterCount))
        }
        return parts.joined(separator: " · ")
    }
}

/// The timeline and its labels. Reads `PlaybackClock.bookTime` for the loaded book (the book's
/// saved position otherwise), so it is the one part of the screen that ticks.
private struct PlayerTimeline: View {
    let model: PlayerViewModel

    @Environment(PlaybackClock.self)
    private var clock
    /// While the finger scrubs, and after it lifts until the clock reports the seek, the slider
    /// shows the scrubbed time instead of the clock, so it doesn't jump back for a tick.
    @State
    private var scrub = Scrub()

    var body: some View {
        let time = model.bookTime(in: clock)
        let book = model.book
        let shown = scrub.time ?? time
        PlayerProgressView(
            currentTime: Binding(get: { scrub.time ?? time }, set: { scrub.drag(to: $0) }),
            totalTime: book.duration,
            centerLabel: book.currentChapter(for: shown).flatMap { index in
                book.chapters.indices.contains(index) ? book.chapters[index].title : nil
            },
            onStartUpdate: { [clock] in
                scrub.drag(to: model.bookTime(in: clock))
            },
            onFinishUpdate: { time in
                model.seek(time)
                scrub.finish()
            }
        )
        .onChange(of: time) {
            scrub.clockMoved()
        }
    }
}

/// The book's download progress (an incomplete LibriVox download): a thin line under the
/// scrubber's labels, and why it waits on this network, if it does. Per-chapter status is in the
/// chapter panel.
private struct PlayerDownloadLine: View {
    let model: PlayerViewModel

    var body: some View {
        let state = model.downloadEntry?.state
        if ChapterListView.showsProgress(state), let state {
            VStack(alignment: .leading, spacing: SpaceConstants.sx4.value) {
                ProgressView(value: state.fraction)
                    .tint(ColorConstants.malachite.value)
                    .scaleEffect(x: 1, y: 0.5)
                    .frame(height: SpaceConstants.sx2.value)
                    .accessibilityIdentifier(AccessibilityID.Player.downloadProgress)
                if let hold = ChapterListView.shownHold(state, hold: model.downloadHold) {
                    Label(hold.message, systemImage: hold.systemImage)
                        .font(.caption)
                        .foregroundColor(ColorConstants.lightSilver.value)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(hold.playerIdentifier)
                }
            }
        }
    }
}

/// The scrubbed time, in a reference type so the slider's touch callbacks (captured once, when its
/// UIKit view is made) always reach the live value. Observable, read only by `PlayerTimeline`.
@MainActor
@Observable
private final class Scrub {
    private(set) var time: Double?
    @ObservationIgnored private var isDragging = false
    @ObservationIgnored private var generation = 0

    func drag(to time: Double) {
        isDragging = true
        if self.time != time { self.time = time }
    }

    /// Keeps the scrubbed time until the clock reports the seek, or 1.5 s if it never does (the
    /// book isn't loaded, or the seek landed on the same second).
    func finish() {
        isDragging = false
        generation += 1
        let current = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self, generation == current, !isDragging else { return }
            clear()
        }
    }

    func clockMoved() {
        guard !isDragging else { return }
        clear()
    }

    private func clear() {
        if time != nil { time = nil }
    }
}

// MARK: - Preview
struct PlayerView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerView(model: PlayerViewModel(
            AudioModel(
                title: "title",
                albumName: "album name",
                artist: "",
                duration: 48_657,
                chapters: [ChapterModel].init(
                    repeating: ChapterModel(title: "Chapter"),
                    count: 3
                )
            ),
            state: PlaybackState(),
            player: nil,
            downloads: nil
        ))
        .environment(PlaybackClock())
        .environment(AppSettings(store: InMemoryKeyValueStore()))
        .environment(PlayerPresentation())
    }
}
