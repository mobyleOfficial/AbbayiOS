//
//  MediaView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 21/06/23.
//

import SwiftUI

/// One library row: cover, title, one line of detail, the download ring and the play button.
///
/// Hard rule: a row that isn't playing does zero work per clock tick. The body reads only
/// `DetailModel`, which reads `PlaybackState` (play, pause and book switches) and the book's own
/// download entry. Only the loaded book's row inserts `RowProgressView`, the one row view that
/// reads `PlaybackClock`.
struct MediaView: View {
    // MARK: - Environment
    @Environment(PlaybackState.self)
    private var playback
    @Environment(\.playbackCenter)
    private var center
    @Environment(\.downloadStateStore)
    private var downloads

    // MARK: - Stored properties
    private let book: AudioModel
    /// Accessibility namespace supplied by the owner, so the same row component can appear on
    /// several screens without identifier collisions.
    private let namespace: String

    // MARK: - Init
    init(_ book: AudioModel, namespace: String = "media") {
        self.book = book
        self.namespace = namespace
    }

    private var actions: MediaViewModel {
        MediaViewModel(book, player: center?.player, downloads: downloads)
    }

    // MARK: - Body
    var body: some View {
        let entry = book.librivoxID.flatMap { downloads?.entry(for: $0) }
        let detail = DetailModel(book: book, state: playback, entry: entry)
        HStack {
            DataImageView(data: book.imageData)
                .accessibilityIdentifier(AccessibilityID.Element.artwork(namespace))
                .frame(side: SpaceConstants.sx64.value)
                .foregroundColor(ColorConstants.white.value)
                .cornerRadius(SpaceConstants.sx8.value)
            VStack(alignment: .leading, spacing: SpaceConstants.sx4.value) {
                PlayerTitleView(isPlaying: .constant(detail.isPlaying), text: book.title)
                    .font(.system(size: SpaceConstants.sx16.value))
                    .accessibilityIdentifier(AccessibilityID.Element.title(namespace))
                detailView(detail)
                    .font(.footnote)
                    .foregroundColor(ColorConstants.lightSilver.value)
                    .lineLimit(1)
                    .accessibilityIdentifier(AccessibilityID.Element.detail(namespace))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, SpaceConstants.sx8.value)
            if let state = detail.downloadState {
                DownloadRingView(state: state) { actions.toggleDownload() }
                    .padding(.leading, SpaceConstants.sx8.value)
                    .accessibilityIdentifier(AccessibilityID.Element.downloadRing(namespace))
            }
            PlayButtonView(isPlaying: .constant(detail.isPlaying)) {
                actions.play()
            } onPause: {
                actions.pause()
            }
            .frame(height: SpaceConstants.sx24.value)
            .padding(.leading, SpaceConstants.sx8.value)
            .accessibilityIdentifier(AccessibilityID.Element.play(namespace))
        }
        .foregroundColor(ColorConstants.white.value)
        .padding(SpaceConstants.sx16.value)
    }

    @ViewBuilder
    private func detailView(_ detail: DetailModel) -> some View {
        if detail.isLoaded {
            RowProgressView(book: book)
        } else {
            Text(detail.detailLine)
        }
    }
}

// MARK: - Detail model
extension MediaView {
    /// Everything an idle row's body reads. It never touches `PlaybackClock`, and it reads
    /// `PlaybackState.isPlaying` only when this row's book is the loaded one, so another book's
    /// play/pause doesn't reach it either.
    struct DetailModel {
        let isLoaded: Bool
        let isPlaying: Bool
        /// From the book's saved fields; the loaded row shows `RowProgressView` instead.
        let detailLine: String
        let downloadState: BookDownloadState?

        init(book: AudioModel, state: PlaybackState, entry: BookDownloadEntry?) {
            isLoaded = book.url != nil && state.loadedBook?.url == book.url
            isPlaying = isLoaded && state.isPlaying
            detailLine = MediaView.detailLine(
                book: book,
                chapterIndex: book.currentChapter(for: book.currentTime) ?? 0,
                bookTime: book.currentTime
            )
            downloadState = entry?.state
        }
    }

    /// `author · Ch N/M` for a chaptered book, `author · <time left>` otherwise. The author and
    /// its separator are dropped when the book has none.
    static func detailLine(book: AudioModel, chapterIndex: Int, bookTime: Double) -> String {
        let progress: String
        if book.chapters.isEmpty {
            progress = Localizable.rowTimeLeft.localized(with: timeLeft(max(book.duration - bookTime, 0)))
        } else {
            let total = book.chapters.count
            progress = Localizable.rowChapter.localized(
                with: ChapterCountView.displayNumber(forIndex: chapterIndex, total: total),
                total
            )
        }
        return book.artist.isEmpty ? progress : "\(book.artist) · \(progress)"
    }

    private static let timeLeftFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    private static func timeLeft(_ seconds: Double) -> String {
        timeLeftFormatter.string(from: seconds.rounded(.down)) ?? ""
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
        .environment(PlaybackState())
        .environment(PlaybackClock())
        .backgroundColor(ColorConstants.background.value)
    }
}
