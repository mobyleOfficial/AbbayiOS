//
//  LibriVoxDetailView.swift
//  Abbay
//

import SwiftUI

/// The LibriVox book page (#166 G5): the cover's tint behind the top, a large centred cover, one
/// metadata line, a full-width Download (then Play) button that pins to the navigation bar once it
/// scrolls away, the description, and the chapters on one glass card.
struct LibriVoxDetailView: View {
    @StateObject
    private var model: LibriVoxDetailViewModel
    @State
    private var isExpanded = false
    /// The big Download/Play button has scrolled under the navigation bar: the compact one shows.
    @State
    private var isActionScrolledAway = false
    /// The cover's average colour, darkened for white text (`CoverTint`), once the cover is in.
    @State
    private var tint: Color?
    /// Beside the player pane the trailing corner is under the top tab bar: the pinned action moves
    /// to the leading side, after the back button (see `isBesidePlayerPane`).
    @Environment(\.isBesidePlayerPane)
    private var isBesidePlayerPane

    init(
        book: LibriVoxBook,
        onAdded: @escaping (AudioModel) -> Void,
        openPlayer: @escaping (AudioModel) -> Void
    ) {
        _model = StateObject(wrappedValue: LibriVoxDetailViewModel(
            book: book,
            client: Self.makeClient(),
            downloads: DependencyContainer.shared.downloads,
            downloadStates: DependencyContainer.shared.downloadStates,
            saveAudio: SaveAudioUseCase(),
            path: NetworkPathMonitor.app,
            cellularPreference: { DependencyContainer.shared.settings.cellularPreference },
            onAdded: onAdded,
            openPlayer: openPlayer
        ))
    }

    private static func makeClient() -> LibriVoxClientProtocol {
        DebugOverrides.libriVoxClient() ?? LibriVoxClient()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { background }
            .foregroundColor(ColorConstants.white.value)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { pinnedAction }
            .accessibilityIdentifier(AccessibilityID.Detail.view)
            .task { await model.load() }
            .task(id: model.book.coverURL) { await loadTint() }
            .alert(
                Localizable.largeDownloadTitle.localized,
                isPresented: $model.isShowingCellularAlert
            ) {
                Button(Localizable.continueDownload.localized) { model.confirmCellular(continue: true) }
                    .accessibilityIdentifier(AccessibilityID.Detail.cellularContinue)
                Button(Localizable.waitForWiFi.localized) { model.confirmCellular(continue: false) }
                    .accessibilityIdentifier(AccessibilityID.Detail.cellularWait)
            } message: {
                Text(Localizable.largeDownloadMessage.localized(with: sizeText))
            }
    }

    // MARK: - Background

    /// The cover's tint at the top, fading into the app background by the middle of the screen.
    /// It stays put while the page scrolls, behind the navigation bar's own scroll edge.
    private var background: some View {
        ZStack {
            ColorConstants.background.value
            LinearGradient(
                colors: [tint ?? ColorConstants.onyx.value, ColorConstants.background.value.opacity(0)],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: Metrics.tintFadeEnd)
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: tint)
    }

    /// Shares the cover's load with the artwork (`AsyncImageLoader` keeps one load per URL). A cover
    /// that can't load leaves the neutral `onyx` tint.
    private func loadTint() async {
        guard let data = await AsyncImageLoader.shared.coverData(for: model.book.coverURL) else { return }
        let color = await Task.detached(priority: .userInitiated) { CoverTint.color(for: data) }.value
        guard !Task.isCancelled else { return }
        tint = Color(uiColor: color)
    }

    // MARK: - Content

    /// archive.org's version of the book as soon as it arrives, with LibriVox's titles and
    /// description shimmering until they follow (#258). Before that, the search result's cover,
    /// title and author, with the rest shimmering.
    @ViewBuilder
    private var content: some View {
        if let details = model.details {
            loaded(details.book, isPlaceholder: false)
        } else if model.loadFailed {
            VStack(spacing: SpaceConstants.sx16.value) {
                Text(Localizable.detailsFailed.localized)
                    .font(.body)
                    .foregroundColor(ColorConstants.lightSilver.value)
                    .multilineTextAlignment(.center)
                Button(Localizable.retry.localized) {
                    Task { await model.load() }
                }
                .abbayGlassButton()
                .accessibilityIdentifier(AccessibilityID.Detail.retry)
            }
            .padding(SpaceConstants.sx32.value)
        } else {
            loaded(model.book, isPlaceholder: true)
        }
    }

    /// `isPlaceholder`: archive.org hasn't answered, so `book` is the light search result.
    private func loaded(_ book: LibriVoxBook, isPlaceholder: Bool) -> some View {
        ScrollView {
            VStack(spacing: SpaceConstants.sx20.value) {
                hero(book, isPlaceholder: isPlaceholder)
                actionButton
                    .disabled(isPlaceholder)
                    .onGeometryChange(for: Bool.self) { proxy in
                        Self.isScrolledAway(maxY: proxy.frame(in: .named(Metrics.scrollSpace)).maxY)
                    } action: { isActionScrolledAway = $0 }
                if isPlaceholder || model.isAwaitingLibriVox {
                    descriptionPlaceholder
                } else {
                    descriptionView(book)
                }
                if isPlaceholder {
                    chapterPlaceholder
                } else {
                    chapterCard(book)
                }
                Text(Localizable.librivoxCredit.localized)
                    .font(.caption)
                    .foregroundColor(ColorConstants.lightSilver.value)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, SpaceConstants.sx20.value)
            .padding(.top, SpaceConstants.sx8.value)
            .padding(.bottom, SpaceConstants.sx32.value)
        }
        .coordinateSpace(name: Metrics.scrollSpace)
    }

    private var sizeText: String {
        ByteSize.text(model.totalBytes)
    }

    // MARK: - Hero

    private func hero(_ book: LibriVoxBook, isPlaceholder: Bool) -> some View {
        VStack(spacing: SpaceConstants.sx8.value) {
            ArtworkView(url: book.coverURL, shadow: true)
                .frame(side: Metrics.cover)
                .padding(.bottom, SpaceConstants.sx8.value)
            Text(book.title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(book.authors)
                .font(.subheadline)
                .foregroundColor(ColorConstants.lightSilver.value)
                .multilineTextAlignment(.center)
            if isPlaceholder {
                ShimmerBar()
                    .frame(width: Metrics.metadataPlaceholderWidth)
                    .padding(.vertical, SpaceConstants.sx2.value)
                    .accessibilityIdentifier(AccessibilityID.Detail.metadataLoading)
            } else {
                Text(Self.metadataText(book: book, totalBytes: model.totalBytes))
                    .font(.footnote)
                    .foregroundColor(ColorConstants.lightSilver.value)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Three shimmering lines where the description goes, the last one shorter.
    private var descriptionPlaceholder: some View {
        VStack(alignment: .leading, spacing: SpaceConstants.sx8.value) {
            ShimmerBar()
            ShimmerBar()
            ShimmerBar()
                .frame(width: Metrics.descriptionLastLineWidth)
        }
        .padding(.vertical, SpaceConstants.sx4.value)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Localizable.loading.localized)
        .accessibilityIdentifier(AccessibilityID.Detail.descriptionLoading)
    }

    /// The chapter card with shimmering rows and no durations, before archive.org answers.
    private var chapterPlaceholder: some View {
        ChapterListView(
            chapters: Array(repeating: ChapterListView.Item(title: "", duration: 0), count: Metrics.placeholderRows),
            layout: .stack,
            chrome: .plain,
            rowIdentifier: AccessibilityID.Detail.chapter,
            titlesLoading: true
        )
        .padding(.bottom, SpaceConstants.sx4.value)
        .abbayGlass(in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Localizable.loading.localized)
        .accessibilityIdentifier(AccessibilityID.Detail.chaptersLoading)
    }

    /// "3h 5m · 12 chapters · 296.7 MB", in the app's language ("3h 5min · 12 capítulos · 296,7 MB").
    /// The size is left out while it is unknown.
    static func metadataText(book: LibriVoxBook, totalBytes: Int64) -> String {
        [
            book.totalSeconds > 0 ? ChapterListView.durationText(book.totalSeconds) : "",
            Localizable.chaptersCount.localized(with: book.sections.count),
            totalBytes > 0 ? ByteSize.text(totalBytes) : ""
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    /// The big button's bottom edge is above the scroll view's top, under the navigation bar.
    static func isScrolledAway(maxY: CGFloat) -> Bool {
        maxY < 0
    }

    private func descriptionView(_ book: LibriVoxBook) -> some View {
        VStack(alignment: .leading, spacing: SpaceConstants.sx4.value) {
            Text(book.descriptionText)
                .font(.subheadline)
                .lineLimit(isExpanded ? nil : 3)
                .foregroundColor(ColorConstants.lightSilver.value)
            if !isExpanded && !book.descriptionText.isEmpty {
                Button(Localizable.more.localized) { isExpanded = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ColorConstants.malachite.value)
                    .accessibilityIdentifier(AccessibilityID.Detail.more)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Download / Play

    private var isAdded: Bool { model.addedBook != nil }

    private func performAction() {
        if isAdded {
            model.play()
        } else {
            model.downloadTapped()
        }
    }

    /// While a Download waits for LibriVox's chapter titles (`isDownloadPending`), a spinner.
    @ViewBuilder
    private var actionLabel: some View {
        if model.isDownloadPending {
            ProgressView()
                .tint(ColorConstants.background2.value)
                .accessibilityLabel(Localizable.loading.localized)
        } else {
            Label(
                isAdded ? Localizable.play.localized : Localizable.download.localized,
                systemImage: isAdded ? "play.fill" : "arrow.down"
            )
        }
    }

    /// One full-width malachite button: Download, then Play once the book is in the library (it
    /// streams what isn't downloaded yet). The download's progress is on the chapter card.
    private var actionButton: some View {
        Button(action: performAction) {
            actionLabel
                .font(.headline)
                .foregroundStyle(ColorConstants.background2.value)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SpaceConstants.sx4.value)
        }
        .abbayGlassProminentButton()
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .accessibilityIdentifier(isAdded ? AccessibilityID.Detail.play : AccessibilityID.Detail.download)
    }

    /// The compact Download/Play in the navigation bar's trailing slot (leading beside the player
    /// pane), once the big one is gone. iOS 26 draws a toolbar button on glass; earlier it is a
    /// plain bar button.
    @ToolbarContentBuilder
    private var pinnedAction: some ToolbarContent {
        if model.details != nil, isActionScrolledAway {
            ToolbarItem(placement: isBesidePlayerPane ? .topBarLeading : .topBarTrailing) {
                Button(action: performAction) {
                    actionLabel
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ColorConstants.malachite.value)
                }
                // A bar button takes the tint, not the label's colour, on iOS 17–25.
                .tint(ColorConstants.malachite.value)
                .accessibilityIdentifier(
                    isAdded ? AccessibilityID.Detail.pinnedPlay : AccessibilityID.Detail.pinnedDownload
                )
            }
        }
    }

    // MARK: - Chapters

    /// The chapter rows on one glass card (one glass layer; the rows inside are plain). Rows are not
    /// tappable: Play opens the player, which is where chapters are chosen. A failed chapter's
    /// status retries it.
    private func chapterCard(_ book: LibriVoxBook) -> some View {
        ChapterListView(
            chapters: book.sections.map(ChapterListView.Item.init),
            downloadState: model.downloadState,
            layout: .stack,
            chrome: .plain,
            progressIdentifier: AccessibilityID.Detail.progress,
            hold: model.downloadHold,
            holdIdentifier: \.detailIdentifier,
            emptyIdentifier: AccessibilityID.Detail.chaptersEmpty,
            rowIdentifier: AccessibilityID.Detail.chapter,
            retry: (AccessibilityID.Detail.chapterRetry, { model.retryChapter($0) }),
            titlesLoading: model.isAwaitingLibriVox,
            titleLoadingIdentifier: AccessibilityID.Detail.chapterTitleLoading
        )
        .padding(.bottom, SpaceConstants.sx4.value)
        .abbayGlass(in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private enum Metrics {
        static let cover: CGFloat = 160
        static let cardRadius: CGFloat = 26
        static let tintFadeEnd: CGFloat = 0.55
        static let scrollSpace = "detail.scroll"
        static let metadataPlaceholderWidth: CGFloat = 180
        static let descriptionLastLineWidth: CGFloat = 200
        static let placeholderRows = 6
    }
}
