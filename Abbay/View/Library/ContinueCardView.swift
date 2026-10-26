//
//  ContinueCardView.swift
//  Abbay
//

import SwiftUI

/// Which book the library's Continue card shows (#166 G3): the last played one
/// (`LastPlayedStore`), if it is still in the library and not listened to the end. Otherwise
/// there is no card.
enum ContinueCard {
    static func book(in books: [AudioModel], lastPlayedURL: URL?) -> AudioModel? {
        guard let lastPlayedURL,
              let book = books.first(where: { $0.url == lastPlayedURL }),
              !DownloadHousekeeping.isFinished(book) else { return nil }
        return book
    }

    /// 0…1 through the whole book; 0 for a book without a duration.
    static func progress(book: AudioModel, bookTime: Double) -> Double {
        guard book.duration > 0, bookTime.isFinite else { return 0 }
        return min(max(bookTime / book.duration, 0), 1)
    }
}

/// The library's Continue card: the cover on a fill in its tint, the title, "Chapter 3 · 28 min
/// left", a Resume (or Pause) capsule and the book's progress. Tapping the card opens the player;
/// the capsule plays or pauses without opening it.
///
/// Like a library cell, it reads `PlaybackClock` only through `ContinueCardProgress`, and only
/// while its book is the loaded one.
struct ContinueCardView: View {
    let book: AudioModel
    let onOpen: () -> Void

    @Environment(PlaybackState.self)
    private var playback
    @Environment(\.playbackCenter)
    private var center
    @Environment(\.downloadStateStore)
    private var downloads

    @ScaledMetric(relativeTo: .body)
    private var coverSide: CGFloat = 94

    private static let cornerRadius: CGFloat = 20

    var body: some View {
        let isLoaded = book.url != nil && playback.loadedBook?.url == book.url
        let isPlaying = isLoaded && playback.isPlaying
        HStack(alignment: .top, spacing: SpaceConstants.sx12.value) {
            ArtworkView(book: book, shadow: true)
                .frame(side: min(coverSide, 140))
                // The player grows out of this cover and collapses back onto it (#241).
                .expansionSource(.continueCard(book))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SpaceConstants.sx4.value) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(Localizable.openPlayer.localized)
                    .accessibilityIdentifier(AccessibilityID.Library.continueTitle)
                ContinueCardProgress(book: book, isLoaded: isLoaded, part: .detail)
                    .font(.footnote)
                    .foregroundColor(ColorConstants.white.value.opacity(0.75))
                    .lineLimit(2)
                    .accessibilityIdentifier(AccessibilityID.Library.continueDetail)
                Spacer(minLength: SpaceConstants.sx8.value)
                HStack(spacing: SpaceConstants.sx12.value) {
                    resumeButton(isPlaying: isPlaying)
                    ContinueCardProgress(book: book, isLoaded: isLoaded, part: .bar)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundColor(ColorConstants.white.value)
        .padding(SpaceConstants.sx12.value)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ContinueCardBackground(book: book, cornerRadius: Self.cornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .onTapGesture(perform: onOpen)
    }

    private func resumeButton(isPlaying: Bool) -> some View {
        Button {
            let actions = MediaViewModel(book, player: center?.player, downloads: downloads)
            if isPlaying {
                actions.pause()
            } else {
                actions.play()
            }
        } label: {
            Label(
                isPlaying ? Localizable.pause.localized : Localizable.resume.localized,
                systemImage: isPlaying ? "pause.fill" : "play.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ColorConstants.background2.value)
            .lineLimit(1)
        }
        .abbayGlassProminentButton()
        .buttonBorderShape(.capsule)
        .fixedSize()
        .accessibilityIdentifier(AccessibilityID.Library.continueResume)
    }
}

/// The card's detail line or progress bar. Only the loaded book's card reads the clock, so an
/// idle card does no work per tick.
private struct ContinueCardProgress: View {
    enum Part {
        case detail
        case bar
    }

    let book: AudioModel
    let isLoaded: Bool
    let part: Part

    var body: some View {
        if isLoaded {
            LiveContinueCardProgress(book: book, part: part)
        } else {
            content(chapter: book.currentChapter(for: book.currentTime) ?? 0, bookTime: book.currentTime)
        }
    }

    @ViewBuilder
    fileprivate func content(chapter: Int, bookTime: Double) -> some View {
        switch part {
        case .detail:
            Text(MiniPlayerActions.subtitle(book: book, chapter: chapter, bookTime: bookTime))
        case .bar:
            ProgressCapsule(fraction: ContinueCard.progress(book: book, bookTime: bookTime), fill: .white)
                .frame(height: SpaceConstants.sx4.value)
                .accessibilityHidden(true)
        }
    }
}

private struct LiveContinueCardProgress: View {
    @Environment(PlaybackClock.self)
    private var clock
    let book: AudioModel
    let part: ContinueCardProgress.Part

    var body: some View {
        ContinueCardProgress(book: book, isLoaded: false, part: part)
            .content(chapter: clock.currentChapter, bookTime: clock.bookTime)
    }
}

/// A thin capsule progress bar on a translucent track: the Continue card's and a library cell's.
struct ProgressCapsule: View {
    let fraction: Double
    var fill: Color = ColorConstants.malachite.value

    var body: some View {
        Capsule()
            .fill(ColorConstants.white.value.opacity(0.15))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(fill)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .clipShape(Capsule())
    }
}

/// The card's fill: the cover's tint (`CoverTint`, the mini player's) shading into black, so white
/// text reads on it whatever the cover. `onyx` until the tint is computed, and for no artwork.
private struct ContinueCardBackground: ViewModifier {
    let book: AudioModel
    let cornerRadius: CGFloat

    @State
    private var tint: UIColor?

    func body(content: Content) -> some View {
        let color = tint ?? CoverTint.cachedTint(for: book) ?? ColorConstants.onyx.uiColor
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(uiColor: color))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(LinearGradient(
                                colors: [.clear, .black.opacity(0.55)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(ColorConstants.white.value.opacity(0.08), lineWidth: 0.5)
                    }
            }
            .task(id: book.url) {
                tint = await CoverTint.tint(for: book)
            }
    }
}
