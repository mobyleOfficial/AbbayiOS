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
    /// The chapter panel is open over the square. The language label and the expand button, glass
    /// buttons, drew over the panel (owner's device test), so they step aside until it closes.
    let hidesControls: Bool

    @Environment(ReadAlongCenter.self)
    private var center
    /// Optional so previews and tests can omit it: there is no expand button then.
    @Environment(PlayerPresentation.self)
    private var presentation: PlayerPresentation?

    init(model: PlayerViewModel, scrub: PlayerScrub, slot: ReadAlongSessionSlot, hidesControls: Bool = false) {
        self.model = model
        self.scrub = scrub
        self.slot = slot
        self.hidesControls = hidesControls
    }

    var body: some View {
        let session = slot.session(from: center)
        ZStack {
            // A dark fill rather than glass: the text is content, not a control.
            RoundedRectangle(cornerRadius: PlayerView.coverRadius, style: .continuous)
                .fill(Color.black.opacity(0.28))
            ReadAlongContent(
                session: session,
                model: model,
                scrub: scrub,
                style: .square,
                hidesControls: hidesControls
            ) {
                EmptyView()
            } trailing: {
                if let presentation {
                    expandButton(presentation)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PlayerView.coverRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Player.readAlong)
        .modifier(ReadAlongSessionDriver(session: session, model: model, scrub: scrub, slot: slot, place: .square))
    }

    /// Bottom-right, opposite the language label: the same text over the whole window. Faded and
    /// out of reach (but kept) while the chapter panel is open, like the label.
    private func expandButton(_ presentation: PlayerPresentation) -> some View {
        ReadAlongCornerButton(
            systemImage: "arrow.up.left.and.arrow.down.right",
            label: Localizable.readAlongFullScreen.localized,
            identifier: AccessibilityID.Player.readAlongExpand,
            isHidden: hidesControls
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
struct ReadAlongContent<Center: View, Trailing: View>: View {
    let session: ReadAlongSession
    let model: PlayerViewModel
    let scrub: PlayerScrub
    let style: ReadAlongStyle
    /// The chapter panel is open over the square: the language label steps aside.
    let hidesControls: Bool
    let center: Center
    let trailing: Trailing

    @ReduceMotion
    private var reduceMotion

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
            // Outside the poll: these change only with the language, the choices or playback.
            HStack(spacing: 0) {
                // Always in the tree, so it keeps its named choices; only its button steps aside
                // while the chapter panel is open (removing the whole view lost the choices, and it
                // never came back).
                ReadAlongLanguageMenu(session: session, isHidden: hidesControls)
                    .frame(maxWidth: .infinity, alignment: .leading)
                center
                trailing
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
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
                    onTap: { model.seek($0.start) }
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
                    onTap: { model.seek($0.start) }
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
/// the choices, not on each render: iOS 26 lists dozens of locales.
private struct ReadAlongLanguageMenu: View {
    let session: ReadAlongSession
    /// The chapter panel is open over the square: the button would draw over it.
    let isHidden: Bool

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
        return Menu {
            ForEach(choices, id: \.id) { choice in
                Button {
                    session.setLanguage(choice.id)
                } label: {
                    if choice.id == language {
                        Label(choice.name, systemImage: "checkmark")
                    } else {
                        Text(choice.name)
                    }
                }
            }
        } label: {
            HStack(spacing: SpaceConstants.sx4.value) {
                Text(name)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundColor(ColorConstants.white.value)
            .padding(.horizontal, SpaceConstants.sx12.value)
            .padding(.vertical, SpaceConstants.sx8.value)
            .abbayGlass(in: Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .accessibilityLabel(Localizable.readAlongLanguage.localized)
        .accessibilityValue(name)
        .accessibilityIdentifier(AccessibilityID.Player.readAlongLanguage)
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
/// `isHidden` fades it and takes it out of reach and out of VoiceOver, but keeps it in place.
struct ReadAlongCornerButton: View {
    let systemImage: String
    let label: String
    let identifier: String
    var isHidden = false
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
        // Disabled as well as hidden: UI tests still list a hidden SwiftUI button, and see this way
        // that it can't be used.
        .disabled(isHidden)
        .accessibilityHidden(isHidden)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
        .opacity(isHidden ? 0 : 1)
        .allowsHitTesting(!isHidden)
        .animation(.easeInOut(duration: 0.2), value: isHidden)
    }
}
