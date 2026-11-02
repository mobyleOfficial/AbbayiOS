//
//  ChaptersPanel.swift
//  Abbay
//

import SwiftUI

/// The player's chapter list as a glass dropdown (#166 G2, `redesign-v3.html`): it grows out of
/// the Chapters pill and floats over the cover; nothing else on the player moves.
///
/// - The header says "Chapters" and the time left in the book.
/// - Rows are `ChapterListView`'s (finished dimmed with a check, the current one malachite with
///   its progress and time left), with the per-chapter download status and "Failed · Retry".
/// - It opens scrolled to the current chapter. A tap on a row plays that chapter (paused or not,
///   of the book on screen; the owner's decision) and closes the panel.
/// - It closes on a tap outside, on the pill (✕), on Escape / the accessibility escape gesture,
///   and on a drag down that starts on its top (the handle and the header).
///
/// Reads the clock for the current row's progress and the header's time left, but its rows redraw
/// only when what they show changes (`ChaptersPanelContent` is `Equatable`).
///
/// `.pane` (#255) is the same list as a persistent pane beside the player, when the window is
/// split: it fills its pane, a chapter tap plays that chapter and leaves it open, and its close
/// button (or the player's ✕ Chapters pill) brings browsing back.
struct ChaptersPanel: View {
    enum Style {
        /// The glass dropdown over the player (one pane).
        case floating
        /// A pane beside the player (split).
        case pane
    }

    let model: PlayerViewModel
    /// The shared chapters state: closing writes it, so the panel never holds a stale callback
    /// (its content is `Equatable`, and SwiftUI keeps the first instance's closures).
    @Binding var isPresented: Bool
    let closeAnimation: Animation
    var style: Style = .floating
    /// The list's real content height, as it is laid out (iOS 18 and later): the floating panel
    /// is sized from it rather than from an estimate per row. Nil: not reported.
    var onListHeight: ((CGFloat) -> Void)?

    @Environment(PlaybackClock.self)
    private var clock
    /// The chapter search, if one is finding more of this book's chapters. Optional so previews can
    /// omit it.
    @Environment(ReadAlongCenter.self)
    private var readAlong: ReadAlongCenter?

    /// The handle and the header: a drag down that starts here closes the panel.
    static let dragHandleHeight: CGFloat = SpaceConstants.sx64.value
    /// How far down such a drag must go to close it.
    static let closeDistance: CGFloat = SpaceConstants.sx48.value
    /// The band at the very top where a tap closes the panel (the handle's).
    static let handleTapHeight: CGFloat = SpaceConstants.sx24.value
    static let cornerRadius: CGFloat = 26

    var body: some View {
        let book = model.book
        let index = model.currentChapter(in: clock)
        let time = model.bookTime(in: clock)
        ChaptersPanelContent(
            model: model,
            isPresented: $isPresented,
            closeAnimation: closeAnimation,
            style: style,
            bookURL: book.url,
            currentIndex: index,
            progress: Self.chapterProgress(chapters: book.chapters, index: index, time: time),
            headerDetail: ChapterListView.timeLeftText(
                duration: book.duration,
                progress: book.duration > 0 ? time / book.duration : 0
            ),
            downloadState: model.downloadEntry?.state,
            searchProgress: readAlong?.chapters.progress(of: book).map { ($0 * 100).rounded(.down) / 100 },
            searchedFraction: readAlong?.chapters.searchedFraction(of: book).map { ($0 * 100).rounded(.down) / 100 },
            onListHeight: onListHeight
        )
        .equatable()
    }

    // MARK: - Decisions

    /// How far into chapter `index` the book time is, 0...1, in steps of 1%, so the rows redraw at
    /// most a hundred times per chapter rather than on every tick. Nil without such a chapter.
    static func chapterProgress(chapters: [ChapterModel], index: Int, time: Double) -> Double? {
        guard chapters.indices.contains(index) else { return nil }
        let chapter = chapters[index]
        guard chapter.duration > 0, time.isFinite else { return 0 }
        let fraction = min(max((time - chapter.startTime) / chapter.duration, 0), 1)
        return (fraction * 100).rounded(.down) / 100
    }

    /// A drag closes the panel when it starts on the panel's top (the handle or the header, not
    /// the list, which scrolls) and goes down far enough, more down than sideways.
    static func closesOnDrag(startY: CGFloat, translation: CGSize) -> Bool {
        startY <= dragHandleHeight
            && translation.height >= closeDistance
            && translation.height > abs(translation.width)
    }
}

/// What the panel draws. `Equatable` on what the rows show, so a clock tick that changes none of
/// it (most ticks) doesn't redraw the list.
private struct ChaptersPanelContent: View, Equatable {
    let model: PlayerViewModel
    @Binding var isPresented: Bool
    let closeAnimation: Animation
    let style: ChaptersPanel.Style
    let bookURL: URL?
    let currentIndex: Int
    let progress: Double?
    let headerDetail: String
    let downloadState: BookDownloadState?
    /// How far a search for more chapters is, in whole percents; nil when none runs.
    let searchProgress: Double?
    /// How much of the book a search that didn't finish covered, in whole percents; nil when the
    /// whole audio was analysed (or no search ran).
    let searchedFraction: Double?
    /// Not compared: SwiftUI keeps the first instance's, and the receiver is the player's state.
    let onListHeight: ((CGFloat) -> Void)?
    /// Where a chapter tap that resumed partway in leaves its prompt (#299). Optional so previews
    /// can omit it.
    @Environment(PlayerPresentation.self)
    private var presentation: PlayerPresentation?
    /// Offers to remove chapters found in the book's audio. Optional so previews can omit it.
    @Environment(ReadAlongCenter.self)
    private var readAlong: ReadAlongCenter?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bookURL == rhs.bookURL
            && lhs.currentIndex == rhs.currentIndex
            && lhs.progress == rhs.progress
            && lhs.headerDetail == rhs.headerDetail
            && lhs.downloadState == rhs.downloadState
            && lhs.searchProgress == rhs.searchProgress
            && lhs.searchedFraction == rhs.searchedFraction
    }

    private func onClose() {
        withAnimation(closeAnimation) { isPresented = false }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChaptersPanel.cornerRadius, style: .continuous)
    }

    @ViewBuilder
    var body: some View {
        switch style {
        case .floating: floating
        case .pane: pane
        }
    }

    private var floating: some View {
        VStack(spacing: 0) {
            handle
            list(closesOnSelect: true)
        }
        // The panel's top (handle and header) is its drag handle: a strip over it that owns the
        // drag, so the list's own scrolling never competes with it (a gesture on the whole panel
        // didn't fire over the list's header, and could hold up the list's pan).
        .abbayGlass(in: shape, tint: Color.black.opacity(0.35))
        .clipShape(shape)
        .contentShape(shape)
        // Over the glass, not inside it: the strip's own gesture then owns touches on the top.
        .overlay(alignment: .top) { dragStrip }
        .accessibilityAction(.escape) { onClose() }
    }

    /// The pane: the book's title over the list, and a close button that brings browsing back. Its
    /// close button carries the panel handle's identifier, so tests close either form the same way.
    private var pane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.book.title)
                    .font(.subheadline)
                    .foregroundColor(ColorConstants.white.value.opacity(0.6))
                    .lineLimit(1)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(side: SpaceConstants.sx36.value)
                        .abbayGlass(in: Circle(), interactive: true)
                        .frame(side: SpaceConstants.sx44.value)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(ColorConstants.white.value)
                .accessibilityLabel(Localizable.closeChapters.localized)
                .accessibilityIdentifier(AccessibilityID.Player.chaptersPanel)
            }
            .padding(.horizontal, SpaceConstants.sx16.value)
            .padding(.top, SpaceConstants.sx8.value)
            list(closesOnSelect: false)
        }
        .accessibilityAction(.escape) { onClose() }
    }

    private func list(closesOnSelect: Bool) -> some View {
        ScrollViewReader { proxy in
            ChapterListView(
                chapters: model.book.chapters.map(ChapterListView.Item.init),
                currentIndex: currentIndex,
                currentProgress: progress,
                downloadState: downloadState,
                layout: .list,
                chrome: .plain,
                headerDetail: headerDetail,
                title: Localizable.chaptersTitle.localized,
                showsBookProgress: false,
                titleIdentifier: AccessibilityID.Player.chaptersTitle,
                rowIdentifier: AccessibilityID.Player.chapter,
                onSelect: { index in
                    if let prompt = model.selectChapter(index) {
                        presentation?.showResumePrompt(prompt)
                    }
                    if closesOnSelect { onClose() }
                },
                retry: (AccessibilityID.Player.chapterRetry, { model.retryChapter($0) }),
                footer: foundChaptersFooter
            )
            .onAppear {
                // Opens with the current chapter in view (the rows' ids are their indices).
                proxy.scrollTo(currentIndex, anchor: .center)
            }
            .modifier(ListContentHeight(onChange: onListHeight))
        }
    }

    /// For chapters found in the book's audio. While more are being found: how far, and *Stop*
    /// (the chapters found so far stay). Stopped short of the end (stopped, failed, the app ended):
    /// how far it got, *Continue finding* (#316) and *Remove found chapters*. Done: where they came
    /// from, and *Remove* (the panel then closes, and the player offers *Find chapters* again).
    private var foundChaptersFooter: ChapterListView.Footer? {
        guard let finder = readAlong?.chapters, !model.book.chapters.isEmpty else { return nil }
        let book = model.book
        if let searchProgress {
            return ChapterListView.Footer(
                note: Localizable.findingMoreChapters.localized(with: FindChaptersPill.percent(searchProgress)),
                actions: [ChapterListView.Footer.Action(
                    title: Localizable.stopFindingChapters.localized,
                    systemImage: "stop.circle",
                    identifier: AccessibilityID.Player.stopFindingChapters
                ) { finder.cancel(book) }]
            )
        }
        guard finder.hasFoundChapters(book) else { return nil }
        let remove = ChapterListView.Footer.Action(
            title: Localizable.removeFoundChapters.localized,
            systemImage: "trash",
            identifier: AccessibilityID.Player.removeFoundChapters,
            role: .destructive
        ) {
            withAnimation(closeAnimation) { finder.removeFoundChapters(book) }
        }
        if let searchedFraction, finder.canContinue(book) {
            let resume = ChapterListView.Footer.Action(
                title: Localizable.continueFindingChapters.localized,
                systemImage: "arrow.clockwise.circle",
                identifier: AccessibilityID.Player.continueFindingChapters
            ) { finder.continueFinding(book) }
            return ChapterListView.Footer(
                note: Localizable.chapterSearchStopped.localized(with: FindChaptersPill.percent(searchedFraction)),
                actions: [resume, remove]
            )
        }
        return ChapterListView.Footer(note: Localizable.foundChaptersNote.localized, actions: [remove])
    }

    /// Transparent, over the handle and the header. One gesture: a drag down closes the panel,
    /// and so does a tap on the handle's own band (the handle under it is VoiceOver's button).
    private var dragStrip: some View {
        Color.clear
            .frame(height: ChaptersPanel.dragHandleHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onEnded { value in
                        let tapped = abs(value.translation.height) < 4 && abs(value.translation.width) < 4
                            && value.startLocation.y <= ChaptersPanel.handleTapHeight
                        if tapped || ChaptersPanel.closesOnDrag(
                            startY: value.startLocation.y,
                            translation: value.translation
                        ) {
                            onClose()
                        }
                    }
            )
            .accessibilityHidden(true)
    }

    /// A small grabber at the top: the panel's handle, and VoiceOver's "Close chapters" button.
    private var handle: some View {
        Capsule()
            .fill(ColorConstants.white.value.opacity(0.3))
            .frame(width: SpaceConstants.sx36.value, height: 4)
            .padding(.top, SpaceConstants.sx8.value)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { onClose() }
            .accessibilityElement()
            .accessibilityLabel(Localizable.closeChapters.localized)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onClose() }
            .accessibilityIdentifier(AccessibilityID.Player.chaptersPanel)
    }
}

/// Reports the height of everything the list holds (its rows and footer, and its insets) as it is
/// laid out, so the panel can be exactly as tall as its content. iOS 18's scroll geometry; on
/// iOS 17 nothing is reported and the panel keeps its estimate.
private struct ListContentHeight: ViewModifier {
    let onChange: ((CGFloat) -> Void)?

    func body(content: Content) -> some View {
        if #available(iOS 18, *), let onChange {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
            } action: { _, height in
                onChange(height)
            }
        } else {
            content
        }
    }
}
