//
//  MediaView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 21/06/23.
//

import SwiftUI

/// One library cell (#166 G3): the square cover, the title on a fixed two-line height, one status
/// line ("New", "Ch 14/135", "3h 20m left", "Finished ✓") and a thin progress bar while started.
/// A LibriVox book that is downloading, or not yet downloaded, has the download ring over the
/// cover's corner. Tapping the cell opens the player (the caller's `onOpen`); its context menu
/// plays or pauses and deletes.
///
/// Hard rule: a cell that isn't playing does zero work per clock tick. The body reads only
/// `DetailModel`, which reads `PlaybackState` (play, pause and book switches) and the book's own
/// download entry. Only the loaded book's cell inserts `RowProgressView`, the one cell view that
/// reads `PlaybackClock`.
struct MediaView: View {
    // MARK: - Environment
    @Environment(PlaybackState.self)
    private var playback
    @Environment(\.playbackCenter)
    private var center
    @Environment(\.downloadStateStore)
    private var downloads
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize
    /// The book the *Rename book* box is open for (#322).
    @State private var renaming: AudioModel?

    // MARK: - Stored properties
    private let book: AudioModel
    /// Accessibility namespace supplied by the owner, so the same cell component can appear on
    /// several screens without identifier collisions.
    private let namespace: String
    /// While the library search has text: a fully downloaded LibriVox book says so on its cover.
    private let showsDownloadedBadge: Bool
    private let onOpen: () -> Void
    private let onDelete: () -> Void

    // MARK: - Init
    init(
        _ book: AudioModel,
        namespace: String = "media",
        showsDownloadedBadge: Bool = false,
        onOpen: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {}
    ) {
        self.book = book
        self.namespace = namespace
        self.showsDownloadedBadge = showsDownloadedBadge
        self.onOpen = onOpen
        self.onDelete = onDelete
    }

    private var actions: MediaViewModel {
        MediaViewModel(book, player: center?.player, downloads: downloads)
    }

    static let coverRadius: CGFloat = 10

    // MARK: - Body
    var body: some View {
        let entry = book.librivoxID.flatMap { downloads?.entry(for: $0) }
        let hold = book.librivoxID.flatMap { downloads?.hold(bookID: $0, allowsCellular: book.allowsCellularDownload) }
        let detail = DetailModel(book: book, state: playback, entry: entry, hold: hold)
        VStack(alignment: .leading, spacing: SpaceConstants.sx4.value) {
            cover(detail)
            Text(book.title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(detail.isPlaying ? ColorConstants.malachite.value : ColorConstants.white.value)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, SpaceConstants.sx4.value)
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(detail.isPlaying ? Localizable.nowPlaying.localized : "")
                .accessibilityAction(named: Self.playbackActionName(detail)) {
                    togglePlayback(detail)
                }
                .accessibilityAction(named: Localizable.delete.localized, onDelete)
                .accessibilityIdentifier(AccessibilityID.Element.title(namespace))
            progressView(detail)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button {
                togglePlayback(detail)
            } label: {
                Label(
                    Self.playbackActionName(detail),
                    systemImage: detail.isPlaying ? "pause.fill" : "play.fill"
                )
            }
            .accessibilityIdentifier(AccessibilityID.Element.play(namespace))
            if BookRenamer.canRename(book) {
                Button {
                    renaming = book
                } label: {
                    Label(Localizable.rename.localized, systemImage: "pencil")
                }
                .accessibilityIdentifier(AccessibilityID.Element.rename(namespace))
            }
            Button(role: .destructive, action: onDelete) {
                Label(Localizable.delete.localized, systemImage: "trash")
            }
            .accessibilityIdentifier(AccessibilityID.Element.delete(namespace))
        }
        .renameBookAlert(for: $renaming) { book, name in
            BookRenamer(playback: center).rename(book, to: name)
        }
    }

    private static func playbackActionName(_ detail: DetailModel) -> String {
        detail.isPlaying ? Localizable.pause.localized : Localizable.play.localized
    }

    private func togglePlayback(_ detail: DetailModel) {
        if detail.isPlaying {
            actions.pause()
        } else {
            actions.play()
        }
    }

    private func cover(_ detail: DetailModel) -> some View {
        ArtworkView(book: book, cornerRadius: Self.coverRadius, shadow: true)
            .aspectRatio(1, contentMode: .fit)
            // The player grows out of this cover and collapses back onto it (#241).
            .expansionSource(.cell(book), cornerRadius: Self.coverRadius)
            .accessibilityIdentifier(AccessibilityID.Element.artwork(namespace))
            .overlay(alignment: .bottomTrailing) {
                if let state = detail.downloadState {
                    DownloadRingView(state: state, hold: detail.downloadHold) { actions.toggleDownload() }
                        .padding(SpaceConstants.sx4.value)
                        .background(Circle().fill(.black.opacity(0.6)))
                        .padding(SpaceConstants.sx4.value)
                        .accessibilityIdentifier(AccessibilityID.Element.downloadRing(namespace))
                }
            }
            .overlay(alignment: .bottomLeading) {
                if showsDownloadedBadge {
                    DownloadedBadge(book: book)
                }
            }
    }

    /// The status line and the progress bar; the loaded cell's follow the clock.
    @ViewBuilder
    private func progressView(_ detail: DetailModel) -> some View {
        if detail.isLoaded {
            RowProgressView(book: book, namespace: namespace)
        } else {
            Self.statusViews(
                line: detail.detailLine,
                fraction: Self.progressFraction(book: book, bookTime: book.currentTime),
                namespace: namespace
            )
        }
    }

    /// The status line and the progress bar's slot. The slot keeps its height when there is no
    /// bar, so every cell in a row is as tall as the others.
    static func statusViews(line: String, fraction: Double?, namespace: String) -> some View {
        VStack(alignment: .leading, spacing: SpaceConstants.sx4.value) {
            Text(line)
                .font(.caption)
                .foregroundColor(ColorConstants.lightSilver.value)
                .lineLimit(1)
                .accessibilityIdentifier(AccessibilityID.Element.detail(namespace))
            ProgressCapsule(fraction: fraction ?? 0)
                .frame(height: 3)
                .opacity(fraction == nil ? 0 : 1)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Detail model
extension MediaView {
    /// Everything an idle cell's body reads. It never touches `PlaybackClock`, and it reads
    /// `PlaybackState.isPlaying` only when this cell's book is the loaded one, so another book's
    /// play/pause doesn't reach it either.
    struct DetailModel {
        let isLoaded: Bool
        let isPlaying: Bool
        /// From the book's saved fields; the loaded cell shows `RowProgressView` instead.
        let detailLine: String
        let downloadState: BookDownloadState?
        /// Why the network holds the download, for the ring (`DownloadStateStore.hold`).
        let downloadHold: NetworkHold?

        init(book: AudioModel, state: PlaybackState, entry: BookDownloadEntry?, hold: NetworkHold? = nil) {
            isLoaded = book.url != nil && state.loadedBook?.url == book.url
            isPlaying = isLoaded && state.isPlaying
            detailLine = MediaView.detailLine(
                book: book,
                chapterIndex: book.currentChapter(for: book.currentTime) ?? 0,
                bookTime: book.currentTime
            )
            downloadState = entry?.state
            downloadHold = hold
        }
    }

    /// The cell's one status line: *Finished ✓* once listened to the end
    /// (`DownloadHousekeeping.isFinished`), *New* before it is started, then *Ch N/M* for a
    /// chaptered book or the time left for one without chapters.
    static func detailLine(book: AudioModel, chapterIndex: Int, bookTime: Double) -> String {
        if isFinished(book: book, bookTime: bookTime) {
            return Localizable.rowFinished.localized
        }
        if bookTime <= 0 {
            return Localizable.rowNew.localized
        }
        if book.chapters.isEmpty {
            return timeLeftLine(book: book, bookTime: bookTime)
        }
        return chapterLine(book: book, chapterIndex: chapterIndex)
    }

    static func chapterLine(book: AudioModel, chapterIndex: Int) -> String {
        let total = book.chapters.count
        return Localizable.rowChapter.localized(
            with: ChapterCountView.displayNumber(forIndex: chapterIndex, total: total),
            total
        )
    }

    static func timeLeftLine(book: AudioModel, bookTime: Double) -> String {
        let left = timeLeft(max(book.duration - bookTime, 0))
        return Localizable.rowTimeLeft.localized(with: left.text, left.count)
    }

    /// 0…1 through the book while it is started and not finished; nil otherwise (no bar).
    static func progressFraction(book: AudioModel, bookTime: Double) -> Double? {
        guard book.duration > 0, bookTime > 0, !isFinished(book: book, bookTime: bookTime) else { return nil }
        return min(bookTime / book.duration, 1)
    }

    private static func isFinished(book: AudioModel, bookTime: Double) -> Bool {
        var at = book
        at.currentTime = bookTime
        return DownloadHousekeeping.isFinished(at)
    }

    private static let timeLeftFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    private static func timeLeft(_ seconds: Double) -> TimeLeftText {
        TimeLeftText(seconds: seconds.rounded(.down), formatter: timeLeftFormatter)
    }
}

// MARK: - Subviews
/// "Downloaded" on the cover of a LibriVox book whose chapters are all on disk, while the library
/// search has text. A badge, so the cell keeps its height. Reads only its own book's entry.
private struct DownloadedBadge: View {
    let book: AudioModel

    @Environment(\.downloadStateStore)
    private var downloads

    var body: some View {
        let state = book.librivoxID.flatMap { downloads?.entry(for: $0).state }
        if LibriVoxIdentity.isFullyDownloaded(book, state: state) {
            Text(Localizable.downloadedTag.localized)
                .font(.caption2.weight(.semibold))
                .foregroundColor(ColorConstants.malachite.value)
                .lineLimit(1)
                .padding(.horizontal, SpaceConstants.sx8.value)
                .padding(.vertical, SpaceConstants.sx2.value)
                .background(Capsule().fill(.black.opacity(0.7)))
                .padding(SpaceConstants.sx4.value)
        }
    }
}

// MARK: - Preview
struct MediaView_Previews: PreviewProvider {
    static var previews: some View {
        MediaView(
            AudioModel(
                title: "title",
                albumName: "album name",
                artist: "author",
                duration: 48_657,
                chapters: [ChapterModel].init(
                    repeating: ChapterModel(),
                    count: 3
                )
            )
        )
        .frame(width: 110)
        .environment(PlaybackState())
        .environment(PlaybackClock())
        .environment(PlayerPresentation())
    }
}
