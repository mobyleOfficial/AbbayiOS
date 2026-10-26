//
//  AsyncImageView.swift
//  Abbay
//

import SwiftUI

/// A remote cover: a shimmering `onyx` tile while it loads, then the image fading in. A failed load
/// shows the generic book tile (`ArtworkPlaceholder`). Screens use it through `ArtworkView(url:)`,
/// which adds the corners, stroke and shadow. Fills the frame it's given (scaled to fill, clipped).
///
/// Images come from `AsyncImageLoader`, so a cover that already loaded shows at once, with no
/// shimmer and no fade. With Reduce Motion the tile doesn't shimmer and the image doesn't fade.
/// Leaving the screen cancels the load (`.task(id:)`).
struct AsyncImageView: View {
    private enum Phase {
        case loading
        case loaded(UIImage)
        case failed
    }

    let url: URL
    private let loader: AsyncImageLoader

    @ReduceMotion
    private var reduceMotion
    @State
    private var phase: Phase

    init(url: URL, loader: AsyncImageLoader = .shared) {
        self.url = url
        self.loader = loader
        _phase = State(initialValue: loader.cachedImage(for: url).map(Phase.loaded) ?? .loading)
    }

    var body: some View {
        ColorConstants.onyx.value
            .overlay { content }
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier(identifier)
            .task(id: url) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            if reduceMotion {
                ColorConstants.onyx.value
            } else {
                ShimmerView()
            }
        case let .loaded(image):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .transition(.opacity)
        case .failed:
            ArtworkPlaceholder(.book)
        }
    }

    private var identifier: String {
        switch phase {
        case .loading: AccessibilityID.Cover.loading
        case .loaded: AccessibilityID.Cover.loaded
        case .failed: AccessibilityID.Cover.failed
        }
    }

    private func load() async {
        // A cache hit (including a new `url` on the same view) shows at once, without a fade.
        if let cached = loader.cachedImage(for: url) {
            phase = .loaded(cached)
            return
        }
        phase = .loading
        let image = await loader.image(for: url)
        // Cancelled: the view left the screen or `url` changed, and a new load owns `phase`.
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.25)) {
            phase = image.map(Phase.loaded) ?? .failed
        }
    }
}

/// A light band sweeping across an `onyx` tile. Driven by the clock rather than a repeating
/// animation, so every tile on screen sweeps in step and a recycled cell never restarts mid-sweep.
private struct ShimmerView: View {
    private static let period: TimeInterval = 1.4
    /// The band's width as a fraction of the tile's.
    private static let bandFraction: CGFloat = 0.6

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                let width = proxy.size.width
                let band = width * Self.bandFraction
                let progress = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: Self.period) / Self.period
                let highlight = ColorConstants.spanishGray.value
                LinearGradient(
                    // Fading the highlight itself, not `clear` (transparent black), keeps the band's
                    // edges from darkening the tile.
                    colors: [highlight.opacity(0), highlight.opacity(0.35), highlight.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: band)
                .offset(x: -band + CGFloat(progress) * (width + band))
            }
        }
        .background(ColorConstants.onyx.value)
    }
}

// MARK: - Preview
struct AsyncImageView_Previews: PreviewProvider {
    static var previews: some View {
        AsyncImageView(url: URL(fileURLWithPath: "/dev/null/cover.jpg"))
            .frame(side: SpaceConstants.sx84.value)
            .cornerRadius(SpaceConstants.sx8.value)
    }
}
