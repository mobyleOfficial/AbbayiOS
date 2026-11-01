//
//  PlayerView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 10/07/23.
//

import SwiftUI

/// The details screen, "Player A" of the Liquid Glass redesign (#166 G1): a large cover, a
/// left-aligned title block, the scrubber, the transport and glass pills (speed, volume, chapters).
/// It is drawn inside the expansion overlay (`PlayerExpansionOverlay`), which paints the cover-tint
/// gradient behind it and adds the header (glass close button, a drag strip) on top.
///
/// The Chapters pill opens the chapter list as a glass panel floating over the cover (G2,
/// `ChaptersPanel`); nothing else on the screen moves. With Read-along on (#192), a Text pill
/// between the two flips the cover's square to the text being read (`ReadAlongView`), like lyrics
/// in Apple Music; again, nothing else moves. The volume pill raises a glass capsule over the
/// screen (`VolumeSlider`): Abbay's own volume, under the system's.
///
/// What it reads, so a clock tick does as little as possible:
/// - this body reads the slow state only (the book, playing or not, via `PlayerViewModel`);
/// - `PlayerTimeline` reads `PlaybackClock.bookTime` and re-renders once per tick;
/// - `PlayerSubtitle` reads `PlaybackClock.currentChapter`, so it re-renders per chapter;
/// - `ReadAlongView`, while the text shows, polls the player every 0.1 s inside itself;
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
    /// Told when the chapter panel or the volume capsule opens or closes: the expansion's cover
    /// handle sits above this screen, under them, and stands aside while either is open, so the
    /// panel's rows take their touches and a tap on the cover closes the capsule.
    private let onChaptersOpen: ((Bool) -> Void)?
    /// Told when the read-along text takes the cover's square, or gives it back: the same handle
    /// stands aside then too, so the lines and the language menu take their taps and drags.
    private let onTextShown: ((Bool) -> Void)?
    /// Skip amounts and speeds. Changes only from Settings or the speed sheet, never on a tick.
    @Environment(AppSettings.self)
    private var settings
    @ReduceMotion
    private var reduceMotion
    /// Compact height (an iPhone in landscape): the cover sits beside the controls (#270).
    @Environment(\.verticalSizeClass)
    private var verticalSizeClass
    @State
    private var isShowingSpeed = false
    /// The volume capsule is up over the pills.
    @State
    private var isShowingVolume = false
    /// Something floats over the cover that takes its touches: the chapter panel or the capsule.
    private var coversHandle: Bool { showsPanel || isShowingVolume }
    /// The scrubbed time, shared by the scrubber and the read-along text, so the text follows the
    /// finger while it drags.
    @State
    private var scrub = PlayerScrub()
    /// Optional so previews and tests can omit it: there is no Text pill then.
    @Environment(ReadAlongCenter.self)
    private var readAlong: ReadAlongCenter?
    /// The read-along session, here rather than in the square, which is rebuilt on each flip and
    /// rotation. One per screen, and the overlay builds one screen per presented book.
    @State
    private var readAlongSlot = ReadAlongSessionSlot()
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
    /// A chapter row's height and the panel's handle and header, estimated at the current text
    /// size, so a short book's panel fits its rows instead of showing empty glass.
    @ScaledMetric(relativeTo: .subheadline)
    private var panelRowHeight: CGFloat = 58
    @ScaledMetric(relativeTo: .headline)
    private var panelChromeHeight: CGFloat = 92
    /// How far a dim (or the volume capsule's tap-catcher) reaches up under the header.
    static let dimReach: CGFloat = 200

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
        onChaptersOpen: ((Bool) -> Void)? = nil,
        onTextShown: ((Bool) -> Void)? = nil
    ) {
        self.model = model
        self.onCoverFrame = onCoverFrame
        self.onChaptersOpen = onChaptersOpen
        self.onTextShown = onTextShown
    }

    // MARK: - Body
    var body: some View {
        AbbayGlassContainer {
            Group {
                if verticalSizeClass == .compact {
                    // Landscape on a phone: the cover fills the height on the leading side, the
                    // rest stacks on the trailing side.
                    HStack(spacing: SpaceConstants.sx24.value) {
                        coverView
                            .overlay(alignment: .bottom) { resumePromptOverlay }
                        VStack(spacing: SpaceConstants.sx12.value) {
                            Spacer(minLength: 0)
                            controls(compact: true)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: SpaceConstants.sx16.value) {
                        // The cover is offered space first, but only what is left once the rest
                        // has its own: it shrinks (staying square) on a short screen.
                        coverView
                            .overlay(alignment: .bottom) { resumePromptOverlay }
                            .layoutPriority(1)
                        controls(compact: false)
                    }
                }
            }
            .padding(.horizontal, Self.margin)
            .padding(.top, SpaceConstants.sx8.value)
            .padding(.bottom, SpaceConstants.sx12.value)
            .overlayPreferenceValue(PillsAnchorKey.self) { pills in
                chaptersOverlay(pills: pills)
            }
            .modifier(VolumeCapsuleOverlay(model: model, isShowing: $isShowingVolume, animation: panelAnimation))
            .onChange(of: coversHandle) { _, open in
                onChaptersOpen?(open)
            }
            .onChange(of: showsText) { _, shown in
                onTextShown?(shown)
                // The pill flipped back or Read-along went off: no text to show full screen.
                if !shown { presentation.endReadAlongFullScreen(of: readAlongSlot) }
            }
            .onAppear {
                onChaptersOpen?(coversHandle)
                onTextShown?(showsText)
            }
            .onDisappear {
                onChaptersOpen?(false)
                onTextShown?(false)
                presentation.endReadAlongFullScreen(of: readAlongSlot)
            }
            .coordinateSpace(.named(Self.layoutSpace))
        }
    }

    /// The title, the scrubber with the download line, the transport and the pills.
    @ViewBuilder
    private func controls(compact: Bool) -> some View {
        titleBlock
        VStack(spacing: SpaceConstants.sx8.value) {
            PlayerTimeline(model: model, scrub: scrub)
            PlayerDownloadLine(model: model)
        }
        playerButtonsView
        pills(compact: compact)
    }

    // MARK: - Cover view
    /// The cover's square: the cover, or the read-along text in its place while the Text pill is
    /// on. Either way it is the square the expansion's growing cover lands on, and hidden until it
    /// has.
    private var coverView: some View {
        coverSquare
            // A square as wide as the screen allows, smaller when the height runs short.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            // The read-along square hides itself (`ReadAlongView`): its fill at once, its text with
            // a fade, so the expansion's copy hands over without a swap.
            .opacity(hidesCover && !showsText ? 0 : 1)
            // Measured on the square that is drawn, not on the `coverSide` frame around it: when
            // the height runs short, that frame is wider than the square, and the expansion's cover
            // grew into it and then snapped down to the real cover as it settled (#254).
            .modifier(FrameReporter(space: Self.coordinateSpace) { frame in
                onCoverFrame?(frame)
            })
            .frame(maxWidth: Self.coverSide, maxHeight: Self.coverSide)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The cover is decoration; the text is read like any other. Under the open chapter panel
            // the square stays drawn (its glass bar stays put) but VoiceOver can't reach it, so the
            // language label and the expand button can't be used behind the panel.
            .accessibilityHidden(!showsText || showsPanel)
            .environment(\.readAlongCoveredByPanel, showsPanel)
    }

    @ViewBuilder
    private var coverSquare: some View {
        if showsText {
            ReadAlongView(model: model, scrub: scrub, slot: readAlongSlot)
        } else {
            ArtworkView(book: model.book, cornerRadius: Self.coverRadius, shadow: true)
        }
    }

    // MARK: - Resume prompt (#299)
    /// "Resumed at 3:20 · Start over" over the bottom of the cover, after a chapter tap resumed
    /// partway in: for this screen's book only, never under the open panel, gone after
    /// `ResumePrompt.duration` or a tap on *Start over*. Nothing else on the screen moves.
    private var resumePromptOverlay: some View {
        VStack {
            if let prompt = presentation.resumePrompt, prompt.bookURL == model.book.url, !showsPanel {
                ResumePromptView(prompt: prompt) {
                    model.restartChapter(prompt.chapterIndex)
                    presentation.dismissResumePrompt()
                }
                .padding(.bottom, SpaceConstants.sx12.value)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .task(id: prompt.id) {
                    try? await Task.sleep(for: ResumePrompt.duration)
                    presentation.dismissResumePrompt(prompt.id)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: presentation.resumePrompt?.id)
    }

    // MARK: - Read-along (#192)
    /// Read-along is on and this device can transcribe (iOS 26+): the Text pill shows.
    private var offersText: Bool {
        settings.readAlongEnabled && readAlong?.isAvailable == true
    }

    /// The text is in the cover's place. Remembered app-wide, so it stays up across books and
    /// launches until flipped back.
    private var showsText: Bool {
        offersText && settings.readAlongShowsText
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

    // MARK: - Chapters panel (G2)

    /// The compact panel is up: the chapters are open and the window is one pane.
    private var showsPanel: Bool {
        isShowingChapters && !paneLayout.isSplit
    }

    @ViewBuilder
    private func chaptersOverlay(pills: Anchor<CGRect>?) -> some View {
        if showsPanel {
            GeometryReader { proxy in
                let frame = ChaptersPanelLayout.frame(
                    container: proxy.size,
                    pillsTop: pills.map { proxy[$0].minY } ?? 0,
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

    var panelAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.82)
    }

    private func setChapters(open: Bool) {
        guard isShowingChapters != open else { return }
        withAnimation(panelAnimation) {
            presentation.setChapters(open: open)
        }
    }
}

// MARK: - Pills
extension PlayerView {
    /// Speed and volume on the left, Chapters on the right, and Text between them while Read-along
    /// is on. A book with no chapters has no Chapters pill.
    /// The speed never shrinks: it read "1…" on a 393 pt iPhone with all four pills. When the row
    /// runs short, Text and then Chapters drop their words and keep their icons (VoiceOver still
    /// reads their names).
    /// They publish their bounds (`PillsAnchorKey`) for the chapter panel, which sits just above
    /// them. A preference, not a stored frame: after a rotation the stored portrait frame placed the
    /// panel off the bottom of the landscape screen, over the pills (#270).
    private func pills(compact: Bool) -> some View {
        HStack {
            HStack(spacing: SpaceConstants.sx8.value) {
                speedPill
                VolumePill(model: model, isShowing: $isShowingVolume, animation: panelAnimation)
            }
            Spacer()
            if offersText {
                textPill
                Spacer(minLength: SpaceConstants.sx8.value)
            }
            if !model.book.chapters.isEmpty {
                chaptersPill
            }
        }
        .anchorPreference(key: PillsAnchorKey.self, value: .bounds) { $0 }
    }

    private var speedPill: some View {
        let speed = model.speed(in: settings)
        return Button {
            isShowingSpeed = true
        } label: {
            PlayerPill(text: PlaybackSpeed.label(speed))
                .monospacedDigit()
        }
        .fixedSize()
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

    /// "Text" with a quote mark; while the text shows, "Cover" with a picture, and VoiceOver reads
    /// it as *Show cover*. A tap flips the square; the cross-fade is the same with Reduce Motion.
    private var textPill: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                settings.readAlongShowsText.toggle()
            }
        } label: {
            PlayerPill(
                text: Self.textPillTitle(showsText: showsText),
                systemImage: showsText ? "photo" : "text.quote",
                collapsesToIcon: true
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(ColorConstants.white.value)
        .accessibilityLabel(
            showsText ? Localizable.readAlongShowCover.localized : Localizable.readAlongPill.localized
        )
        .accessibilityIdentifier(AccessibilityID.Player.text)
    }

    /// What a tap on the Text pill shows: the text over the cover, the cover over the text.
    static func textPillTitle(showsText: Bool) -> String {
        showsText ? Localizable.readAlongCoverPill.localized : Localizable.readAlongPill.localized
    }

    /// "☰ Chapters", or "✕ Chapters" while the panel is open; a tap toggles it.
    private var chaptersPill: some View {
        Button {
            setChapters(open: !isShowingChapters)
        } label: {
            PlayerPill(
                text: Localizable.chaptersTitle.localized,
                systemImage: isShowingChapters ? "xmark" : "list.bullet",
                collapsesToIcon: true
            )
        }
        // Keeps its word longer than Text: the row's own way in to the chapters.
        .layoutPriority(1)
        .buttonStyle(.plain)
        .foregroundColor(ColorConstants.white.value)
        .accessibilityLabel(
            isShowingChapters ? Localizable.closeChapters.localized : Localizable.chaptersTitle.localized
        )
        .accessibilityIdentifier(AccessibilityID.Player.chapters)
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

/// Where the pills are, for the chapter panel above them. The last one reported wins: the layout
/// on screen.
private struct PillsAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// Reports a view's frame in a named space: its first value as well as every change, so a layout
/// that appears already in place after a rotation (#270) reports where its cover is.
private struct FrameReporter: ViewModifier {
    let space: String
    let action: (CGRect) -> Void

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.frame(in: .named(space)), initial: true) { _, frame in
                        action(frame)
                    }
            }
        }
    }
}

/// A glass capsule with a label, the look of the speed and chapters pills. The volume pill has
/// only its icon, at a fixed width, so the pill keeps its size as the symbol changes. With
/// `collapsesToIcon`, a pill offered less than its full width shows only its icon, at that same
/// width, instead of truncating its word; its button keeps its accessibility label.
struct PlayerPill: View {
    let text: String?
    var systemImage: String?
    /// For a symbol that draws a level: the volume's waves.
    var variableValue: Double?
    var collapsesToIcon = false

    @ScaledMetric(relativeTo: .subheadline)
    private var iconOnlyWidth: CGFloat = 22

    var body: some View {
        Group {
            if collapsesToIcon, systemImage != nil, text != nil {
                ViewThatFits(in: .horizontal) {
                    content(showsText: true)
                    content(showsText: false)
                }
            } else {
                content(showsText: true)
            }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        // 12, not 16: with Read-along on, four pills share a 393 pt iPhone's row with their words.
        .padding(.horizontal, SpaceConstants.sx12.value)
        .padding(.vertical, SpaceConstants.sx8.value + SpaceConstants.sx2.value)
        .abbayGlass(in: Capsule(), interactive: true)
        .contentShape(Capsule())
    }

    private func content(showsText: Bool) -> some View {
        let shownText = showsText ? text : nil
        return HStack(spacing: SpaceConstants.sx4.value) {
            if let systemImage {
                Image(systemName: systemImage, variableValue: variableValue)
                    .frame(width: shownText == nil ? iconOnlyWidth : nil)
                    .accessibilityHidden(true)
            }
            if let shownText {
                Text(shownText)
            }
        }
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
    /// While the finger scrubs, and after it lifts until the clock reports the seek, the slider
    /// shows the scrubbed time instead of the clock, so it doesn't jump back for a tick.
    let scrub: PlayerScrub

    @Environment(PlaybackClock.self)
    private var clock

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
/// UIKit view is made) always reach the live value. Observable, read only by the leaves that show
/// the time: `PlayerTimeline`, and `ReadAlongView`, whose text follows the finger.
@MainActor
@Observable
final class PlayerScrub {
    private(set) var time: Double?
    /// A finger is on the scrubber. `time` outlives it until the seek lands; this doesn't.
    /// Not observed: the read-along square reads it on its own 0.1 s poll.
    @ObservationIgnored private(set) var isDragging = false
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
