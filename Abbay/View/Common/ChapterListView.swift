//
//  ChapterListView.swift
//  Abbay
//

import SwiftUI

/// The chapter list of the player sheet and the LibriVox page: a rounded card with a "Chapters"
/// header bar, a thin overall progress bar while a download is incomplete, and one row per
/// chapter with its scrolling title, its download status and its duration.
struct ChapterListView: View {
    struct Item: Equatable {
        let title: String
        let duration: Double
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
    /// The row drawn in malachite, if any.
    var currentIndex: Int?
    var downloadState: BookDownloadState?
    /// The player dims its list while paused.
    var isDimmed = false
    var layout: Layout = .list
    var titleIdentifier: String?
    var progressIdentifier: String?
    let rowIdentifier: (Int) -> String
    /// Rows are tappable only when set.
    var onSelect: ((Int) -> Void)?
    /// A failed chapter's status becomes a retry button, with this identifier, only when set.
    var retry: (identifier: (Int) -> String, action: (Int) -> Void)?
    /// The details screen's collapse from the list's top (iOS 18+, `.list` layout only).
    var listCollapse: ExpansionListCollapse?

    private var spacing: CGFloat { SpaceConstants.sx16.value }

    // MARK: - Decisions
    static func showsProgress(_ state: BookDownloadState?) -> Bool {
        guard let state else { return false }
        return !state.isComplete
    }

    static func status(at index: Int, in state: BookDownloadState?) -> ChapterDownloadState? {
        guard let state, state.chapters.indices.contains(index) else { return nil }
        return state.chapters[index]
    }

    /// The row shows a retry button: its chapter failed and the screen can retry it.
    static func canRetry(at index: Int, in state: BookDownloadState?, hasRetryAction: Bool) -> Bool {
        hasRetryAction && status(at: index, in: state) == .failed
    }

    // MARK: - Body
    var body: some View {
        VStack {
            header
            if Self.showsProgress(downloadState), let downloadState {
                ProgressView(value: downloadState.fraction)
                    .tint(ColorConstants.malachite.value)
                    .scaleEffect(x: 1, y: 0.5)
                    .frame(height: SpaceConstants.sx2.value)
                    .accessibilityIdentifier(ifPresent: progressIdentifier)
            }
            rows
        }
        .background(ColorConstants.background.value)
        .cornerRadius(SpaceConstants.sx32.value)
        .opacity(isDimmed ? 0.5 : 1.0)
    }

    private var header: some View {
        HStack {
            Text(Localizable.chapterSelectionTitle.localized)
                .foregroundColor(ColorConstants.white.value)
                .font(.system(size: SpaceConstants.sx16.value))
                .accessibilityIdentifier(ifPresent: titleIdentifier)
            Spacer()
        }
        .padding(spacing)
        .background(ColorConstants.background2.value)
    }

    @ViewBuilder
    private var rows: some View {
        let items = Array(chapters.enumerated())
        switch layout {
        case .list:
            List {
                ForEach(items, id: \.offset) { index, chapter in
                    row(index, chapter)
                        .listRowBackground(ColorConstants.clear.value)
                        .listRowInsets(.init(all: spacing))
                        // Otherwise the separator starts under the duration, the row's first `Text`.
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }
            }
            .listStyle(.plain)
            .modifier(ListCollapseModifier(handler: listCollapse))
        case .stack:
            LazyVStack(spacing: 0) {
                ForEach(items, id: \.offset) { index, chapter in
                    row(index, chapter)
                        .padding(spacing)
                    // Stands in for the plain `List`'s separator, which follows every row.
                    Divider()
                        .padding(.horizontal, spacing)
                }
            }
        }
    }

    private func row(_ index: Int, _ chapter: Item) -> some View {
        let canRetry = Self.canRetry(at: index, in: downloadState, hasRetryAction: retry != nil)
        return HStack {
            PlayerTitleView(isPlaying: .constant(currentIndex == index), text: chapter.title)
            if let status = Self.status(at: index, in: downloadState) {
                ChapterDownloadStatusView(
                    state: status,
                    retry: retry.map { retry in (retry.identifier(index), { retry.action(index) }) }
                )
            }
            Text(chapter.duration.timestamp)
                .font(.caption)
                .foregroundColor(ColorConstants.spanishGray.value)
        }
        .font(.system(size: SpaceConstants.sx16.value))
        .contentShape(Rectangle())
        // A retry button stays its own element, so VoiceOver and UI tests can reach it.
        .accessibilityElement(children: canRetry ? .contain : .combine)
        .accessibilityIdentifier(rowIdentifier(index))
        .selectable(onSelect.map { onSelect in { onSelect(index) } })
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
                .init(title: "A much longer chapter title that has to scroll", duration: 3725)
            ],
            currentIndex: 0,
            downloadState: BookDownloadState(
                chapters: [.downloaded, .downloading(fraction: 0.4)],
                isPaused: false,
                fraction: 0.7
            ),
            rowIdentifier: { "preview.chapter.\($0)" }
        )
        .padding()
        .preferredColorScheme(.dark)
    }
}
