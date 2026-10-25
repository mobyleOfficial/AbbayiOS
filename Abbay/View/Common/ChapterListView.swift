//
//  ChapterListView.swift
//  Abbay
//

import SwiftUI

/// The chapter list of the player sheet and the LibriVox page: a "Chapters" header, a thin
/// overall progress bar while a download is incomplete, and one row per chapter.
///
/// Rows (#166 G6, `redesign-v3.html`): the number, the title (up to two lines, never truncated
/// into the trailing column), the download status, and the duration ("1h 5m", "42m"). Chapters
/// before the current one are *finished*: dimmed, with a check instead of the duration. The
/// *current* one is malachite on a faint malachite fill, with a ▶︎ marker instead of its number
/// and, when `currentProgress` is given, a thin progress bar under the title and "28m left".
struct ChapterListView: View {
    struct Item: Equatable {
        let title: String
        let duration: Double
    }

    /// Where a row's chapter sits relative to the one playing.
    enum RowState: Equatable {
        case finished
        case current
        case upcoming
    }

    /// The surface behind the list.
    enum Chrome {
        /// An opaque rounded card with a header bar. Today's player sheet and LibriVox page.
        case card
        /// No fill and no clipping, for a caller that puts the list on its own glass
        /// (`abbayGlass(in:)`): the G2 dropdown panel and the G5 chapter card.
        case plain
    }

    enum Layout {
        /// A `List` that scrolls by itself and fills the space it is given. The player sheet.
        case list
        /// Rows in a `LazyVStack`, sized to their content, for a page that is already a scroll
        /// view. A `List` nested in a `ScrollView` has no intrinsic height and collapses.
        case stack
    }

    // MARK: - Properties
    let chapters: [Item]
    /// The row drawn in malachite, if any. Rows before it are finished.
    var currentIndex: Int?
    /// How far into the current chapter playback is, 0...1. When set, the current row shows a
    /// progress bar and its time left instead of its duration. Reading it re-renders the list, so
    /// pass it only from a view that already updates with the clock.
    var currentProgress: Double?
    var downloadState: BookDownloadState?
    var layout: Layout = .list
    var chrome: Chrome = .card
    /// Secondary text at the header's trailing edge, e.g. the time left in the book.
    var headerDetail: String?
    /// The header's title. "Chapter selection" unless the caller names it (the G2 panel says
    /// "Chapters").
    var title: String?
    /// The book's download progress bar and network hint above the rows. The player shows them on
    /// its own screen (under the scrubber) and turns them off in the chapter panel.
    var showsBookProgress = true
    var titleIdentifier: String?
    var progressIdentifier: String?
    /// Why the download is waiting on this network, said under the progress bar (see `shownHold`).
    var hold: NetworkHold?
    var holdIdentifier: ((NetworkHold) -> String)?
    /// The "No chapters" message shown instead of rows when there are none.
    var emptyIdentifier: String?
    let rowIdentifier: (Int) -> String
    /// Rows are tappable only when set.
    var onSelect: ((Int) -> Void)?
    /// A failed chapter's status becomes a retry button, with this identifier, only when set.
    var retry: (identifier: (Int) -> String, action: (Int) -> Void)?

    /// The leading column (number or ▶︎), wide enough for "999" at the current text size.
    @ScaledMetric(relativeTo: .subheadline)
    private var numberWidth: CGFloat = 28

    private var spacing: CGFloat { SpaceConstants.sx16.value }

    // MARK: - Decisions
    /// Finished before the current chapter, current at it, upcoming after it. With no current
    /// chapter (the LibriVox page), every row is upcoming.
    static func rowState(at index: Int, currentIndex: Int?) -> RowState {
        guard let currentIndex else { return .upcoming }
        if index < currentIndex { return .finished }
        return index == currentIndex ? .current : .upcoming
    }

    /// A chapter's length in whole minutes, rounded up so a short chapter never reads "0m":
    /// "42m", "1h 5m" (pt-BR "42min", "1h 5min"), in the app's language.
    static func durationText(_ seconds: Double) -> String {
        minutes(seconds).text
    }

    /// The current row's trailing text: its time left ("28m left", "28min restantes").
    static func timeLeftText(duration: Double, progress: Double) -> String {
        let left = minutes(duration * (1 - min(max(progress, 0), 1)))
        return Localizable.rowTimeLeft.localized(with: left.text, left.count)
    }

    private static func minutes(_ seconds: Double) -> TimeLeftText {
        let safe = seconds.isFinite ? max(seconds, 0) : 0
        let minutes = (safe / 60).rounded(.up)
        return TimeLeftText(seconds: minutes * 60, formatter: durationFormatter)
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        // Drops a zero minute: exactly one hour reads "1h", not "1h 0m" (#152).
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    /// A book with no chapter markers (a plain MP3) says so, rather than showing an empty card.
    static func showsEmptyState(_ chapters: [Item]) -> Bool {
        chapters.isEmpty
    }

    static func showsProgress(_ state: BookDownloadState?) -> Bool {
        guard let state else { return false }
        return !state.isComplete
    }

    /// Why a Wait-for-Wi-Fi book isn't moving: cellular, a Personal Hotspot or Low Data Mode, which
    /// its tasks are kept off (#148, #171). Only while the progress bar shows, so never for a
    /// finished book.
    static func shownHold(_ state: BookDownloadState?, hold: NetworkHold?) -> NetworkHold? {
        showsProgress(state) ? hold : nil
    }

    static func status(at index: Int, in state: BookDownloadState?) -> ChapterDownloadState? {
        guard let state, state.chapters.indices.contains(index) else { return nil }
        return state.chapters[index]
    }

    /// The download status a row shows. A *finished* chapter that is downloaded shows nothing:
    /// its "finished" check already fills the trailing column, and two checks meaning different
    /// things read as noise (#225). Every other status (downloading, waiting, failed) still shows.
    static func shownStatus(
        at index: Int,
        in state: BookDownloadState?,
        rowState: RowState
    ) -> ChapterDownloadState? {
        let status = status(at: index, in: state)
        if rowState == .finished, status == .downloaded { return nil }
        return status
    }

    /// The row shows a retry button: its chapter failed and the screen can retry it.
    static func canRetry(at index: Int, in state: BookDownloadState?, hasRetryAction: Bool) -> Bool {
        hasRetryAction && status(at: index, in: state) == .failed
    }

    // MARK: - Body
    var body: some View {
        VStack {
            header
            if showsBookProgress, Self.showsProgress(downloadState), let downloadState {
                ProgressView(value: downloadState.fraction)
                    .tint(ColorConstants.malachite.value)
                    .scaleEffect(x: 1, y: 0.5)
                    .frame(height: SpaceConstants.sx2.value)
                    .accessibilityIdentifier(ifPresent: progressIdentifier)
            }
            if showsBookProgress, let shown = Self.shownHold(downloadState, hold: hold) {
                holdHint(shown)
            }
            if Self.showsEmptyState(chapters) {
                emptyState
            } else {
                rows
            }
        }
        .modifier(CardChrome(chrome: chrome))
    }

    /// Styled like the library's empty state: a glyph over the text. In the player sheet it fills
    /// the space the list would have.
    private var emptyState: some View {
        VStack(spacing: SpaceConstants.sx8.value) {
            Image(systemName: "list.bullet")
                .resizable()
                .scaledToFit()
                .frame(width: SpaceConstants.sx24.value)
                .foregroundColor(ColorConstants.spanishGray.value)
                .accessibilityHidden(true)
            Text(Localizable.noChaptersTitle.localized)
                .foregroundColor(ColorConstants.white.value)
                .font(.body)
            Text(Localizable.noChaptersMessage.localized)
                .foregroundColor(ColorConstants.lightSilver.value)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .padding(SpaceConstants.sx24.value)
        .frame(maxWidth: .infinity, maxHeight: layout == .list ? .infinity : nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(ifPresent: emptyIdentifier)
    }

    private func holdHint(_ hold: NetworkHold) -> some View {
        Label(hold.message, systemImage: hold.systemImage)
            .font(.caption)
            .foregroundColor(ColorConstants.lightSilver.value)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, spacing)
            .padding(.top, SpaceConstants.sx8.value)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(ifPresent: holdIdentifier?(hold))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title ?? Localizable.chapterSelectionTitle.localized)
                .foregroundColor(ColorConstants.white.value)
                .font(.headline)
                .accessibilityIdentifier(ifPresent: titleIdentifier)
            Spacer()
            if let headerDetail {
                Text(headerDetail)
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(Self.secondary)
            }
        }
        .padding(spacing)
        .background(chrome == .card ? ColorConstants.background2.value : ColorConstants.clear.value)
    }

    // MARK: - Row colours (white opacities over the surface, per the mockups)
    private static let secondary = ColorConstants.white.value.opacity(0.55)
    private static let dimmed = ColorConstants.white.value.opacity(0.5)
    private static let currentFill = ColorConstants.malachite.value.opacity(0.12)
    private static let track = ColorConstants.white.value.opacity(0.15)

    @ViewBuilder
    private var rows: some View {
        let items = Array(chapters.enumerated())
        switch layout {
        case .list:
            List {
                ForEach(items, id: \.offset) { index, chapter in
                    row(index, chapter)
                        .listRowBackground(rowFill(index))
                        .listRowInsets(
                            EdgeInsets(
                                top: Self.rowVerticalPadding,
                                leading: spacing,
                                bottom: Self.rowVerticalPadding,
                                trailing: spacing
                            )
                        )
                        // Otherwise the separator starts under the number, the row's first `Text`.
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        case .stack:
            LazyVStack(spacing: 0) {
                ForEach(items, id: \.offset) { index, chapter in
                    row(index, chapter)
                        .padding(.vertical, Self.rowVerticalPadding)
                        .padding(.horizontal, spacing)
                        .background(rowFill(index))
                    // Stands in for the plain `List`'s separator, which follows every row.
                    Divider()
                        .padding(.horizontal, spacing)
                }
            }
        }
    }

    private static let rowVerticalPadding = SpaceConstants.sx12.value

    private func rowFill(_ index: Int) -> Color {
        Self.rowState(at: index, currentIndex: currentIndex) == .current
            ? Self.currentFill
            : ColorConstants.clear.value
    }

    private func row(_ index: Int, _ chapter: Item) -> some View {
        let canRetry = Self.canRetry(at: index, in: downloadState, hasRetryAction: retry != nil)
        let state = Self.rowState(at: index, currentIndex: currentIndex)
        return HStack(alignment: .firstTextBaseline, spacing: SpaceConstants.sx12.value) {
            leadingMark(index, state: state)
            VStack(alignment: .leading, spacing: SpaceConstants.sx4.value) {
                Text(chapter.title)
                    .font(.subheadline.weight(state == .current ? .semibold : .regular))
                    .foregroundColor(Self.titleColor(state))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if state == .current, let currentProgress {
                    progressBar(currentProgress)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let status = Self.shownStatus(at: index, in: downloadState, rowState: state) {
                ChapterDownloadStatusView(
                    state: status,
                    retry: retry.map { retry in (retry.identifier(index), { retry.action(index) }) }
                )
            }
            trailing(chapter, state: state)
        }
        .contentShape(Rectangle())
        // A retry button stays its own element, so VoiceOver and UI tests can reach it.
        .accessibilityElement(children: canRetry ? .contain : .combine)
        .accessibilityAddTraits(state == .current ? .isSelected : [])
        .accessibilityIdentifier(rowIdentifier(index))
        .selectable(onSelect.map { onSelect in { onSelect(index) } })
    }

    private static func titleColor(_ state: RowState) -> Color {
        switch state {
        case .finished: dimmed
        case .current: ColorConstants.malachite.value
        case .upcoming: ColorConstants.white.value
        }
    }

    /// The chapter number, or ▶︎ on the current chapter.
    private func leadingMark(_ index: Int, state: RowState) -> some View {
        Group {
            if state == .current {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundColor(ColorConstants.malachite.value)
                    .accessibilityLabel(Localizable.chapterCurrent.localized)
            } else {
                Text(String(index + 1))
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(Self.secondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: numberWidth, alignment: .leading)
    }

    /// The duration; a check on a finished chapter; the time left on the current one when its
    /// progress is known.
    private func trailing(_ chapter: Item, state: RowState) -> some View {
        Group {
            switch state {
            case .finished:
                Image(systemName: "checkmark.circle")
                    .foregroundColor(Self.dimmed)
                    .accessibilityLabel(Localizable.chapterFinished.localized)
            case .current:
                Text(
                    currentProgress.map { Self.timeLeftText(duration: chapter.duration, progress: $0) }
                        ?? Self.durationText(chapter.duration)
                )
                .fontWeight(.semibold)
                .foregroundColor(ColorConstants.malachite.value)
            case .upcoming:
                Text(Self.durationText(chapter.duration))
                    .foregroundColor(Self.secondary)
            }
        }
        .font(.footnote.monospacedDigit())
        // One line at its full width: the title wraps instead.
        .lineLimit(1)
        .fixedSize()
    }

    private func progressBar(_ progress: Double) -> some View {
        Capsule()
            .fill(Self.track)
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(ColorConstants.malachite.value)
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
                }
            }
            .accessibilityHidden(true)
    }
}

/// The `.card` chrome: an opaque rounded card. `.plain` leaves the surface to the caller.
private struct CardChrome: ViewModifier {
    let chrome: ChapterListView.Chrome

    func body(content: Content) -> some View {
        switch chrome {
        case .card:
            content
                .background(ColorConstants.background.value)
                .cornerRadius(SpaceConstants.sx32.value)
        case .plain:
            content
        }
    }
}

extension ChapterListView.Item {
    init(_ chapter: ChapterModel) {
        self.init(title: chapter.title, duration: chapter.duration)
    }

    init(_ section: LibriVoxBook.Section) {
        self.init(title: section.title, duration: section.seconds)
    }
}

private extension View {
    @ViewBuilder
    func accessibilityIdentifier(ifPresent identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }

    @ViewBuilder
    func selectable(_ action: (() -> Void)?) -> some View {
        if let action {
            onTapGesture(perform: action)
        } else {
            self
        }
    }
}

// MARK: - Preview
struct ChapterListView_Previews: PreviewProvider {
    static var previews: some View {
        ChapterListView(
            chapters: [
                .init(title: "Chapter 1", duration: 754),
                .init(title: "A much longer chapter title that wraps onto a second line", duration: 3725),
                .init(title: "Chapter 3", duration: 2520)
            ],
            currentIndex: 1,
            currentProgress: 0.38,
            downloadState: BookDownloadState(
                chapters: [.downloaded, .downloaded, .downloading(fraction: 0.4)],
                isPaused: false,
                fraction: 0.7
            ),
            headerDetail: "7h 26m left",
            rowIdentifier: { "preview.chapter.\($0)" }
        )
        .padding()
        .preferredColorScheme(.dark)
    }
}
