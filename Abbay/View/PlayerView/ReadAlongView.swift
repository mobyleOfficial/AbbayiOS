//
//  ReadAlongView.swift
//  Abbay
//

import SwiftUI

/// The read-along text in the player's cover square (#192, option A): the text takes the cover's
/// place, like lyrics in Apple Music, and nothing else on the player moves. Its expand button
/// shows the same text over the whole window (`ReadAlongFullScreenView`).
///
/// It drives the screen's `ReadAlongSession` while it is on screen, and only then
/// (`ReadAlongSessionDriver`): `show` when it appears, when the screen follows another book and
/// when the app comes back; `stop` when it leaves the screen (the pill flips back, the player
/// closes, Read-along is turned off) and when the app leaves the foreground. Nothing transcribes
/// while the text is hidden.
///
/// The session isn't this view's: `PlayerView` owns it (`ReadAlongSessionSlot`), because this view
/// is rebuilt each time the pill flips back and forth or the phone turns (the cover sits in another
/// branch of the layout). A session of its own would load the transcript and check the language
/// and model again each time, flashing *Preparing text…*.
///
/// The shown time is the scrubber's while a finger drags it (shown, but no run starts until the
/// finger lifts), else the player's own time (`PlayerViewModel.liveBookTime`), polled every 0.1 s by
/// a `TimelineView` inside this view only, so the rest of the player doesn't re-render on each poll.
struct ReadAlongView: View {
    let model: PlayerViewModel
    let scrub: PlayerScrub

    /// The player screen's session, made the first time the text shows.
    let slot: ReadAlongSessionSlot

    /// The square's fill, under the text. The expansion's growing cover turns into it as it lands.
    static let fill = Color.black.opacity(0.28)

    @Environment(ReadAlongCenter.self)
    private var center
    /// Optional so previews and tests can omit it: there is no expand button then.
    @Environment(PlayerPresentation.self)
    private var presentation: PlayerPresentation?
    /// The expansion draws the square while it grows or shrinks (`PlayerExpansionOverlay`), turning
    /// the artwork into this fill: the fill hands over at once, the text and the controls fade.
    @Environment(\.expansionDrawsPlayerCover)
    private var isDrawnByExpansion

    var body: some View {
        let session = slot.session(from: center)
        ZStack {
            // A dark fill rather than glass: the text is content, not a control. Hidden at once
            // while the expansion draws it: its copy is the same fill in the same place.
            RoundedRectangle(cornerRadius: PlayerView.coverRadius, style: .continuous)
                .fill(Self.fill)
                .opacity(isDrawnByExpansion ? 0 : 1)
            ReadAlongContent(
                session: session,
                model: model,
                scrub: scrub,
                style: .square,
                // Under the full screen, and while the expansion moves: a glass control is
                // composited by its container whatever its parent's opacity, so a fade alone
                // left them over the growing cover.
                hidesControls: isDrawnByExpansion || presentation?.readAlongFullScreen != nil
            ) {
                EmptyView()
            } trailing: {
                if let presentation {
                    expandButton(presentation)
                }
            }
            // The text fades in as the square lands, and quickly out as it starts to shrink.
            .opacity(isDrawnByExpansion ? 0 : 1)
            .animation(
                isDrawnByExpansion ? .easeOut(duration: 0.12) : .easeIn(duration: 0.22),
                value: isDrawnByExpansion
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: PlayerView.coverRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Player.readAlong)
        .modifier(ReadAlongSessionDriver(session: session, model: model, scrub: scrub, slot: slot, place: .square))
    }

    /// Bottom-right, opposite the language label: the same text over the whole window. It stays
    /// while the chapter panel is open, under the panel, like the label (`ReadAlongContent`).
    private func expandButton(_ presentation: PlayerPresentation) -> some View {
        ReadAlongCornerButton(
            systemImage: "arrow.up.left.and.arrow.down.right",
            label: Localizable.readAlongFullScreen.localized,
            identifier: AccessibilityID.Player.readAlongExpand
        ) {
            presentation.showReadAlongFullScreen(ReadAlongFullScreen(model: model, scrub: scrub, slot: slot))
        }
    }

    // MARK: - Language menu

    /// One language-menu entry: the locale id and what the menu calls it.
    struct LanguageChoice: Equatable {
        let id: String
        let name: String
    }

    /// The menu's entries, in alphabetical order of their names. A choice is named by its language
    /// alone ("English"), unless another choice shares that language: both then carry their region
    /// ("English (United Kingdom)", "English (United States)"), in the in-app language.
    static func languageChoices(_ ids: [String], in locale: Locale = AbbayBundle.locale) -> [LanguageChoice] {
        let languages = ids.map { ReadAlongLanguage.displayName($0, in: locale) }
        let choices = zip(ids, languages).map { id, language in
            let isShared = languages.filter { $0 == language }.count > 1
            let regional = locale.localizedString(forIdentifier: id.replacingOccurrences(of: "_", with: "-"))
                .map { $0.prefix(1).uppercased(with: locale) + $0.dropFirst() }
            return LanguageChoice(id: id, name: isShared ? regional ?? id : language)
        }
        return choices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Session slot

/// One player screen's read-along session, held by `PlayerView` so it outlives the square: the
/// square is rebuilt on every flip of the Text pill and every rotation, and the session's language,
/// model check and loaded transcript must not be redone each time. Made lazily, the first time the
/// text shows, so a screen that never shows it costs nothing.
///
/// It also counts where the session is on screen: in a rotation the new layout's square can appear
/// before the old one disappears, and the old one's `stop` must not stop the session the new one
/// shows. The full-screen text (`ReadAlongFullScreenView`) shows the same session and counts too, so
/// the square under it may come and go.
@MainActor
final class ReadAlongSessionSlot {
    /// Where the session's text is on screen.
    enum Place {
        case square
        case fullScreen
    }

    private var session: ReadAlongSession?
    private var onScreen: [Place: Int] = [:]

    /// The session, made with `center` the first time it is asked for.
    func session(from center: ReadAlongCenter) -> ReadAlongSession {
        if let session { return session }
        let made = center.makeSession()
        session = made
        return made
    }

    func appeared(_ place: Place = .square) {
        onScreen[place, default: 0] += 1
    }

    /// True when nothing shows the session any more, square or full screen: time to stop it.
    func disappeared(_ place: Place = .square) -> Bool {
        onScreen[place] = max((onScreen[place] ?? 0) - 1, 0)
        return onScreen.values.allSatisfy { $0 == 0 }
    }
}

// MARK: - Session driver

/// Drives the session while its text is on screen, for the square and the full screen alike: shown
/// when the view appears, when the app comes back and when the screen follows another book; stopped
/// when the last view showing it goes (`ReadAlongSessionSlot`) or the app leaves the foreground.
struct ReadAlongSessionDriver: ViewModifier {
    let session: ReadAlongSession
    let model: PlayerViewModel
    let scrub: PlayerScrub
    let slot: ReadAlongSessionSlot
    let place: ReadAlongSessionSlot.Place

    @Environment(\.scenePhase)
    private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear {
                slot.appeared(place)
                show()
            }
            .onDisappear {
                // After a rotation the new square may appear before the old one goes, and the
                // full screen shows the session too: it stops only once nothing shows it.
                if slot.disappeared(place) {
                    session.stop()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    show()
                } else {
                    session.stop()
                }
            }
            // The screen follows the loaded book after a switch (Siri, CarPlay, Play on another book).
            .onChange(of: model.book.url) { show() }
            // A chapter that finishes downloading can be transcribed now: the text appears by itself.
            .onChange(of: downloadedChapters) {
                session.downloadsChanged(model.book)
            }
    }

    /// Which of the shown book's chapters are on the device; nil once complete or for an imported
    /// book. Progress within a chapter isn't in it, so a download's ticks don't reach the session.
    private var downloadedChapters: [Bool]? {
        model.downloadEntry?.state?.chapters.map { $0 == .downloaded }
    }

    private func show() {
        guard scenePhase == .active else { return }
        session.show(model.book, at: scrub.time ?? model.liveBookTime())
    }
}

// MARK: - Style

/// The square's text, or the full screen's: larger there, and kept to a readable column so a wide
/// window (an iPad, landscape) doesn't run a line from edge to edge.
enum ReadAlongStyle {
    case square
    case fullScreen

    var lineStyle: Font.TextStyle {
        switch self {
        case .square: .title2
        case .fullScreen: .title
        }
    }

    /// The text column's widest; nil fills the square.
    var maxLineWidth: CGFloat? {
        switch self {
        case .square: nil
        case .fullScreen: 600
        }
    }

    fileprivate var statusFont: Font {
        switch self {
        case .square: .headline
        case .fullScreen: .title3.weight(.semibold)
        }
    }

    fileprivate var lineMargin: CGFloat {
        switch self {
        case .square: SpaceConstants.sx20.value
        case .fullScreen: SpaceConstants.sx24.value
        }
    }
}

// MARK: - Content

/// The lines, or a message when there is nothing to show yet, over a bar along the bottom: the
/// language label on the left, `trailing` on the right (the square's expand button, the full
/// screen's collapse button) and `center` between them (the full screen's play/pause). The one part
/// that ticks: it re-renders on each 0.1 s poll, while the lines redraw only when the line or word
/// to highlight changes (`ReadAlongLines` is `Equatable`).
///
/// The bar's controls hide after 3 s with no interaction (`ReadAlongControlsVisibility`, owner's
/// "prioritize immersion"). While they are hidden the first tap anywhere only brings them back (it
/// doesn't seek); while they show, a tap does what it does and starts the delay again, as does
/// scrolling the lines. Hidden controls are left out of the hierarchy, never faded: the glass
/// container composites a glass control whatever its parent's opacity.
///
/// The bar's glass is a container of its own, not the player's: in the player's container the
/// chapter panel's glass merged with the label's and the expand button's, so the buttons drew over
/// the open panel, and when they were taken out instead the panel morphed out of the expand button
/// (owner's device tests). On their own they composite with the square, under the panel, and stay.
struct ReadAlongContent<Center: View, Trailing: View>: View {
    let session: ReadAlongSession
    let model: PlayerViewModel
    let scrub: PlayerScrub
    let style: ReadAlongStyle
    /// Something covers the text (the full screen) or draws it (the expansion, moving): the
    /// language label and `trailing` step aside.
    let hidesControls: Bool
    let center: Center
    let trailing: Trailing

    @ReduceMotion
    private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled)
    private var voiceOver
    @State
    private var controls = ReadAlongControlsVisibility()
    @State
    private var isMenuOpen = false

    init(
        session: ReadAlongSession,
        model: PlayerViewModel,
        scrub: PlayerScrub,
        style: ReadAlongStyle,
        hidesControls: Bool,
        @ViewBuilder center: () -> Center,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.session = session
        self.model = model
        self.scrub = scrub
        self.style = style
        self.hidesControls = hidesControls
        self.center = center()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let time = scrub.time ?? model.liveBookTime()
                text(at: time)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: context.date) {
                        // While the finger drags, the text follows it but nothing transcribes:
                        // the run starts where it lifts.
                        session.timeChanged(time, isScrubbing: scrub.isDragging)
                    }
            }
            // Outside the poll: these change only with the language, the choices, playback or
            // the controls' visibility.
            bar
        }
        // The whole text takes a tap, not only its lines.
        .contentShape(Rectangle())
        // Hidden: the first tap only brings the controls back, ahead of a line's seek.
        .highPriorityGesture(revealTap, including: controls.isHidden ? .all : .subviews)
        // Showing: a tap does what it does, and starts the delay again.
        .simultaneousGesture(revealTap, including: controls.isHidden ? .subviews : .all)
        .onAppear { controls.reveal() }
        .onDisappear { controls.stop() }
        .onChange(of: isPinned, initial: true) { _, pinned in
            controls.setPinned(pinned)
        }
    }

    private var showsControls: Bool {
        !hidesControls && !controls.isHidden
    }

    private var isPinned: Bool {
        ReadAlongControlsVisibility.isPinned(
            voiceOver: voiceOver,
            menuOpen: isMenuOpen,
            state: session.state,
            covered: hidesControls
        )
    }

    private var revealTap: some Gesture {
        TapGesture().onEnded { controls.reveal() }
    }

    private var bar: some View {
        AbbayGlassContainer {
            barContent
        }
    }

    private var barContent: some View {
        HStack(spacing: 0) {
            // Always in the tree, so it keeps its named choices; only its button steps aside
            // (removing the whole view lost the choices, and it never came back).
            ReadAlongLanguageMenu(session: session, isHidden: !showsControls) { isOpen in
                isMenuOpen = isOpen
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Left out, not faded: the shared glass container composites a glass button itself,
            // so a parent's opacity didn't hide it on a device (owner's device test). A fade, no
            // movement, so Reduce Motion needs nothing else.
            ZStack {
                if showsControls {
                    center
                        .transition(.opacity)
                }
            }
            ZStack {
                if showsControls {
                    trailing
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .animation(.easeInOut(duration: 0.25), value: showsControls)
    }

    @ViewBuilder
    private func text(at time: Double) -> some View {
        if session.state == .ready, let transcript = session.transcript {
            switch transcript.display(at: time) {
            case let .line(position):
                ReadAlongLines(
                    lines: transcript.lines,
                    current: position.line,
                    isSpoken: true,
                    // With Reduce Motion, only the line: a word lighting up every half second is
                    // motion too.
                    word: reduceMotion ? nil : position.word,
                    animates: !reduceMotion,
                    style: style,
                    onTap: { model.seek($0.start) },
                    onScroll: { controls.reveal() }
                )
                .equatable()
            case let .upcoming(line):
                // An intro or a pause: the next line waits in the middle, dimmed, and lights up in
                // place when the narrator reaches it.
                ReadAlongLines(
                    lines: transcript.lines,
                    current: line,
                    isSpoken: false,
                    word: nil,
                    animates: !reduceMotion,
                    style: style,
                    onTap: { model.seek($0.start) },
                    onScroll: { controls.reveal() }
                )
                .equatable()
            case .music:
                ReadAlongMusic()
            }
        } else {
            ReadAlongStatus(
                message: ReadAlongContentText.message(for: session.state),
                isWorking: ReadAlongContentText.isWorking(session.state),
                font: style.statusFont
            )
        }
    }
}

/// What the text says while there is no line to show.
private enum ReadAlongContentText {
    static func message(for state: ReadAlongState) -> String {
        switch state {
        case .preparing, .ready:
            Localizable.readAlongPreparing.localized
        case let .downloadingModel(locale):
            Localizable.readAlongDownloadingModel.localized(with: ReadAlongLanguage.displayName(locale))
        case let .unsupported(locale):
            Localizable.readAlongUnsupported.localized(with: ReadAlongLanguage.displayName(locale))
        case .needsDownload:
            Localizable.readAlongNeedsDownload.localized
        case .fileMissing:
            Localizable.readAlongFileMissing.localized
        case .failed:
            Localizable.readAlongFailed.localized
        }
    }

    static func isWorking(_ state: ReadAlongState) -> Bool {
        switch state {
        case .preparing, .downloadingModel: true
        default: false
        }
    }
}

// MARK: - Language menu

/// *English ▾* in the bottom-leading corner, once the language is known. It stays when iOS can't
/// transcribe that language, so another can be picked. The entries are named once per change of
/// the choices, not on each render: iOS 26 lists dozens of locales. The menu itself is a UIKit
/// button (`ReadAlongLanguageMenuButton`), which reports when it opens and closes.
private struct ReadAlongLanguageMenu: View {
    let session: ReadAlongSession
    /// The controls hid with no interaction, or something covers or draws the text
    /// (`ReadAlongContent.hidesControls`).
    let isHidden: Bool
    /// The menu opened (true) or closed: the controls stay while it is open, since it hangs off
    /// the label.
    let onOpenChange: (Bool) -> Void

    @State
    private var choices: [ReadAlongView.LanguageChoice] = []

    var body: some View {
        // A container rather than a `Group`: a `Group` hands its modifiers to its content, and with
        // nothing to show yet the choices were never named (the full screen, which opens with the
        // choices already known, never showed the label) and the bar's frame had nothing to size.
        ZStack {
            if !isHidden, let language = session.language, !choices.isEmpty {
                menu(language: language)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isHidden)
        .onChange(of: session.choices, initial: true) { _, ids in
            choices = ReadAlongView.languageChoices(ids)
        }
    }

    private func menu(language: String) -> some View {
        let name = ReadAlongLanguage.displayName(language)
        return HStack(spacing: SpaceConstants.sx4.value) {
            Text(name)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .foregroundColor(ColorConstants.white.value)
        .padding(.horizontal, SpaceConstants.sx12.value)
        .padding(.vertical, SpaceConstants.sx8.value)
        // Not interactive: the clear UIKit button over it takes every touch.
        .abbayGlass(in: Capsule(), interactive: false)
        // The capsule only draws; the clear UIKit button over it is the control, and says when its
        // menu opens and closes (SwiftUI's `Menu` doesn't).
        .accessibilityHidden(true)
        .overlay {
            ReadAlongLanguageMenuButton(
                choices: choices,
                current: language,
                name: name,
                onPick: { session.setLanguage($0) },
                onOpenChange: onOpenChange
            )
        }
        .padding(SpaceConstants.sx12.value)
    }
}

// MARK: - Lines

/// The transcript, the current line kept in the middle of the square (or of the full screen, in a
/// centred column). The current line is white and semibold, with the spoken word in malachite;
/// lines already read are faint, upcoming ones a little less. The top and bottom edges fade out.
///
/// Lazy, so a whole book's transcript costs only the rows on screen. A tap on a line seeks to its
/// start (`PlayerViewModel.seek`, which does nothing for a book that isn't loaded).
private struct ReadAlongLines: View, Equatable {
    let lines: [ReadAlongLine]
    /// The line kept in the middle: the one being read, or the one coming when `isSpoken` is false.
    let current: Int
    let isSpoken: Bool
    let word: Int?
    let animates: Bool
    let style: ReadAlongStyle
    let onTap: (ReadAlongLine) -> Void
    /// A finger scrolls the lines: an interaction, like a tap.
    let onScroll: () -> Void

    @ScaledMetric(relativeTo: .title2)
    private var squareSpacing: CGFloat = 14
    @ScaledMetric(relativeTo: .title)
    private var fullScreenSpacing: CGFloat = 18

    private var spacing: CGFloat {
        style == .square ? squareSpacing : fullScreenSpacing
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.current == rhs.current && lhs.isSpoken == rhs.isSpoken && lhs.word == rhs.word
            && lhs.animates == rhs.animates && lhs.style == rhs.style && lhs.lines == rhs.lines
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: spacing) {
                        ForEach(lines.indices, id: \.self) { index in
                            line(index)
                        }
                    }
                    .frame(maxWidth: style.maxLineWidth)
                    .padding(.horizontal, style.lineMargin)
                    .frame(maxWidth: .infinity)
                    // Half the square above and below, so the first and last lines can sit in its
                    // middle too.
                    .padding(.vertical, proxy.size.height / 2)
                }
                .mask(Self.fade)
                .modifier(ReadAlongScrollWatch(onScroll: onScroll))
                .onAppear {
                    reader.scrollTo(current, anchor: .center)
                }
                .onChange(of: current) { _, line in
                    if animates {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            reader.scrollTo(line, anchor: .center)
                        }
                    } else {
                        reader.scrollTo(line, anchor: .center)
                    }
                }
            }
        }
    }

    private func line(_ index: Int) -> some View {
        let isCurrent = isSpoken && index == current
        let opacity: Double = isCurrent ? 1 : index < current ? 0.35 : 0.55
        return Text(Self.text(of: lines[index], highlighting: isCurrent ? word : nil))
            .font(.system(style.lineStyle, weight: isCurrent ? .semibold : .regular))
            .foregroundColor(ColorConstants.white.value.opacity(opacity))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onTap(lines[index]) }
            .id(index)
            .accessibilityIdentifier(AccessibilityID.Player.readAlongLine(index))
            // A tap seeks there, so VoiceOver offers it as a button. It can find the line being
            // spoken; nothing is announced as it moves on.
            .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(Localizable.readAlongLineHint.localized)
    }

    /// The line's words, the highlighted one in malachite.
    private static func text(of line: ReadAlongLine, highlighting word: Int?) -> AttributedString {
        var result = AttributedString()
        for (index, item) in line.words.enumerated() {
            if index > 0 { result += AttributedString(" ") }
            var part = AttributedString(item.text)
            if index == word {
                part.foregroundColor = ColorConstants.malachite.value
            }
            result += part
        }
        return result
    }

    private static var fade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.22),
                .init(color: .black, location: 0.68),
                // Gone by the language label, which sits over the bottom edge.
                .init(color: .clear, location: 0.9)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Calls `onScroll` when a finger scrolls the lines (not when the current line scrolls itself into
/// place). iOS 18 and later; read-along needs iOS 26 anyway.
private struct ReadAlongScrollWatch: ViewModifier {
    let onScroll: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .interacting { onScroll() }
            }
        } else {
            content
        }
    }
}

// MARK: - Music

/// ♪ for a long stretch with no speech (an intro, an interlude, the music after a chapter): a
/// sentence there read as an error. VoiceOver still says *No speech here*.
private struct ReadAlongMusic: View {
    var body: some View {
        Image(systemName: "music.note")
            .font(.largeTitle)
            .imageScale(.large)
            .foregroundColor(ColorConstants.white.value.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement()
            .accessibilityLabel(Localizable.readAlongNoSpeech.localized)
            .accessibilityIdentifier(AccessibilityID.Player.readAlongStatus)
    }
}

// MARK: - Status

/// Why there is no text to show: preparing, a model downloading, no audio on the device, no speech,
/// a failure. Centred in the square, with a spinner while something is under way.
private struct ReadAlongStatus: View {
    let message: String
    let isWorking: Bool
    let font: Font

    var body: some View {
        VStack(spacing: SpaceConstants.sx12.value) {
            if isWorking {
                ProgressView()
                    .tint(ColorConstants.white.value)
            }
            Text(message)
                .font(font)
                .multilineTextAlignment(.center)
                .foregroundColor(ColorConstants.white.value.opacity(0.8))
        }
        .padding(SpaceConstants.sx24.value)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Player.readAlongStatus)
    }
}

// MARK: - Corner button

/// A glass circle in a corner of the text, the language label's look: the square's expand button
/// and the full screen's collapse button. The hit area takes the corner's margin too, so it is
/// larger than the circle.
///
/// It has no hidden state: a glass button is hidden by leaving it out of the hierarchy
/// (`ReadAlongContent`), since the glass container draws it whatever its parent's opacity.
struct ReadAlongCornerButton: View {
    let systemImage: String
    let label: String
    let identifier: String
    let action: () -> Void

    /// The language label's height at the default text size.
    @ScaledMetric(relativeTo: .caption)
    private var side: CGFloat = 32

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundColor(ColorConstants.white.value)
                .frame(side: side)
                .abbayGlass(in: Circle(), interactive: true)
                .padding(SpaceConstants.sx12.value)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
