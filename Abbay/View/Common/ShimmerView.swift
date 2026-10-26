//
//  ShimmerView.swift
//  Abbay
//

import SwiftUI

/// A light band sweeping across an `onyx` tile. Driven by the clock rather than a repeating
/// animation, so every tile on screen sweeps in step and a recycled cell never restarts mid-sweep.
struct ShimmerView: View {
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

/// A rounded shimmering bar standing in for a line of text that is still loading: the LibriVox
/// page's description and chapter titles while LibriVox answers (#258). With Reduce Motion it is
/// a still `onyx` bar. Read by VoiceOver as "Loading".
struct ShimmerBar: View {
    var height: CGFloat = SpaceConstants.sx12.value

    @ReduceMotion
    private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                ColorConstants.onyx.value
            } else {
                ShimmerView()
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel(Localizable.loading.localized)
    }
}
