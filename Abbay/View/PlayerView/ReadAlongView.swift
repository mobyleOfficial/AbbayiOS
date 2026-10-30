//
//  ReadAlongView.swift
//  Abbay
//

import SwiftUI

/// The read-along text in the player's cover square (#192, option A): the text takes the cover's
/// place, like lyrics in Apple Music, and nothing else on the player moves.
///
/// It drives the screen's `ReadAlongSession` while it is on screen, and only then: `show` when it
/// appears, when the screen follows another book and when the app comes back; `stop` when it
/// leaves the screen (the pill flips back, the player closes, Read-along is turned off) and when
/// the app leaves the foreground. Nothing transcribes while the text is hidden.
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

    @Environment(ReadAlongCenter.self)
    private var center
    @Environment(\.scenePhase)
    private var scenePhase

    init(model: PlayerViewModel, scrub: PlayerScrub, slot: ReadAlongSessionSlot) {
        self.model = model
        self.scrub = scrub
        self.slot = slot
    }

    private var session: ReadAlongSession {
        slot.session(from: center)
    }

    var body: some View {
        ZStack {
            // A dark fill rather than glass: the text is content, not a control.
            RoundedRectangle(cornerRadius: PlayerView.coverRadius, style: .continuous)
                .fill(Color.black.opacity(0.28))
            ReadAlongContent(session: session, model: model, scrub: scrub)
        }
        .clipShape(RoundedRectangle(cornerRadius: PlayerView.coverRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Player.readAlong)
        .onAppear {
            slot.appeared()
            show()
        }
        .onDisappear {
            // After a rotation the new square may appear before the old one goes: the session
            // stops only once no square shows it.
            if slot.disappeared() {
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
/// It also counts the squares on screen: in a rotation the new layout's square can appear before
/// the old one disappears, and the old one's `stop` must not stop the session the new one shows.
@MainActor
final class ReadAlongSessionSlot {
    private var session: ReadAlongSession?
    private var squaresOnScreen = 0

    /// The session, made with `center` the first time it is asked for.
    func session(from center: ReadAlongCenter) -> ReadAlongSession {
        if let session { return session }
        let made = center.makeSession()
        session = made
        return made
    }

    func appeared() {
        squaresOnScreen += 1
    }

    /// True when no square shows the session any more: it is time to stop it.
    func disappeared() -> Bool {
        squaresOnScreen = max(squaresOnScreen - 1, 0)
        return squaresOnScreen == 0
    }
}

// MARK: - Content

/// The lines, or a message when there is nothing to show yet, and the language label. The one
/// part that ticks: it re-renders on each 0.1 s poll, while the lines redraw only when the line or
/// word to highlight changes (`ReadAlongLines` is `Equatable`).
private struct ReadAlongContent: View {
    let session: ReadAlongSession
    let model: PlayerViewModel
    let scrub: PlayerScrub

    @ReduceMotion
    private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottomLeading) {
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
            // Outside the poll: it changes only with the language or the choices.
            ReadAlongLanguageMenu(session: session)
        }
    }

    @ViewBuilder
    private func text(at time: Double) -> some View {
        if session.state == .ready, let transcript = session.transcript {
            if let position = transcript.position(at: time) {
                ReadAlongLines(
                    lines: transcript.lines,
                    current: position.line,
                    // With Reduce Motion, only the line: a word lighting up every half second is
                    // motion too.
                    word: reduceMotion ? nil : position.word,
                    animates: !reduceMotion,
                    onTap: { model.seek($0.start) }
                )
                .equatable()
            } else {
                ReadAlongStatus(message: Localizable.readAlongNoSpeech.localized, isWorking: false)
            }
        } else {
            ReadAlongStatus(message: Self.message(for: session.state), isWorking: Self.isWorking(session.state))
        }
    }

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

    private static func isWorking(_ state: ReadAlongState) -> Bool {
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

    @State
    private var choices: [ReadAlongView.LanguageChoice] = []

    var body: some View {
        Group {
            if let language = session.language, !choices.isEmpty {
                menu(language: language)
            }
        }
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

/// The transcript, the current line kept in the middle of the square. The current line is white
/// and semibold, with the spoken word in malachite; lines already read are faint, upcoming ones a
/// little less. The top and bottom edges fade out.
///
/// Lazy, so a whole book's transcript costs only the rows on screen. A tap on a line seeks to its
/// start (`PlayerViewModel.seek`, which does nothing for a book that isn't loaded).
private struct ReadAlongLines: View, Equatable {
    let lines: [ReadAlongLine]
    let current: Int
    let word: Int?
    let animates: Bool
    let onTap: (ReadAlongLine) -> Void

    @ScaledMetric(relativeTo: .title2)
    private var spacing: CGFloat = 14

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.current == rhs.current && lhs.word == rhs.word && lhs.animates == rhs.animates && lhs.lines == rhs.lines
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
                    .padding(.horizontal, SpaceConstants.sx20.value)
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
        let isCurrent = index == current
        let opacity: Double = isCurrent ? 1 : index < current ? 0.35 : 0.55
        return Text(Self.text(of: lines[index], highlighting: isCurrent ? word : nil))
            .font(.title2.weight(isCurrent ? .semibold : .regular))
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

// MARK: - Status

/// Why there is no text to show: preparing, a model downloading, no audio on the device, no speech,
/// a failure. Centred in the square, with a spinner while something is under way.
private struct ReadAlongStatus: View {
    let message: String
    let isWorking: Bool

    var body: some View {
        VStack(spacing: SpaceConstants.sx12.value) {
            if isWorking {
                ProgressView()
                    .tint(ColorConstants.white.value)
            }
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(ColorConstants.white.value.opacity(0.8))
        }
        .padding(SpaceConstants.sx24.value)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Player.readAlongStatus)
    }
}
