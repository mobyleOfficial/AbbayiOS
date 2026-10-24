//
//  ExpansionMath.swift
//  Abbay
//

import CoreGraphics
import Foundation

/// The pure half of the mini player's expansion into the details screen: how a vertical drag maps
/// to a 0…1 progress, whether a release settles open, when a collapse may start, and how the frame,
/// corner radius and fades interpolate. `PlayerExpansionOverlay` draws with these.
enum ExpansionMath {
    /// Released past 30% of the travel settles open (and, collapsing, past 30% settles closed).
    static let openThreshold: CGFloat = 0.30
    /// A flick faster than this (pt/s) settles in its direction regardless of the distance.
    static let flickVelocity: CGFloat = 800
    /// The strip the expansion grows from when no bar is visible: the bar's height, along the
    /// bottom edge.
    static let bottomStripHeight: CGFloat = 56

    /// `start` plus the drag's share of `travel`, clamped to 0…1. Dragging up (negative y) opens.
    static func progress(start: CGFloat, translationY: CGFloat, travel: CGFloat) -> CGFloat {
        guard travel > 0 else { return clamp(start) }
        return clamp(start - translationY / travel)
    }

    /// Opening: past 30%, or an upward flick. Closing is the mirror: it stays open only while above
    /// 70% and not flicked down.
    static func shouldOpen(progress: CGFloat, velocityY: CGFloat, wasOpening: Bool) -> Bool {
        if wasOpening {
            return progress >= openThreshold || velocityY <= -flickVelocity
        }
        return progress > 1 - openThreshold && velocityY < flickVelocity
    }

    /// A collapse starts from the header or grabber anywhere, and from the chapter list only when
    /// it is scrolled to the top; otherwise the list scrolls.
    static func canStartCollapse(listOffset: CGFloat, fromHeader: Bool) -> Bool {
        fromHeader || listOffset <= 0
    }

    /// The bar's one drag is the expansion when it starts more vertical than horizontal, and a
    /// chapter swipe otherwise.
    static func isVerticalDrag(_ translation: CGSize) -> Bool {
        abs(translation.height) > abs(translation.width)
    }

    /// How far back `releaseVelocity` looks.
    static let releaseWindow: TimeInterval = 0.06

    /// The release speed: the gesture's reported velocity, or the speed over the 60 ms before the
    /// release when that is faster. A stationary sample right before the lift (a synthesized drag,
    /// or a finger that hesitates for one frame) can drop the reported velocity of a flick to near
    /// 0. The window ends at `releaseTime` (the lift), not at the last sample: a finger held still
    /// sends no samples, so a hold after a fast move leaves the window without the fast part and
    /// the release stays slow. Without `releaseTime` the window ends at the last sample.
    static func releaseVelocity(
        reported: CGFloat,
        samples: [(time: TimeInterval, translationY: CGFloat)],
        releaseTime: TimeInterval? = nil
    ) -> CGFloat {
        guard let last = samples.last else { return reported }
        // The finger stays at its last translation until the lift.
        let end = max(last.time, releaseTime ?? last.time)
        guard let first = samples.first(where: { end - $0.time <= releaseWindow }),
              end > first.time else { return reported }
        let windowed = (last.translationY - first.translationY) / CGFloat(end - first.time)
        return abs(windowed) > abs(reported) ? windowed : reported
    }

    /// Linear interpolation between two rects; `fraction` 0 gives `from`, 1 gives `to`.
    static func interpolate(_ from: CGRect, _ to: CGRect, _ fraction: CGFloat) -> CGRect {
        CGRect(
            x: lerp(from.minX, to.minX, fraction),
            y: lerp(from.minY, to.minY, fraction),
            width: lerp(from.width, to.width, fraction),
            height: lerp(from.height, to.height, fraction)
        )
    }

    /// Where the expansion starts: the bar's frame, or the bottom strip when there is no bar.
    static func startFrame(bar: CGRect?, screen: CGSize) -> CGRect {
        if let bar { return bar }
        return CGRect(x: 0, y: screen.height - bottomStripHeight, width: screen.width, height: bottomStripHeight)
    }

    /// The bar's content fades out over the first 30%.
    static func barContentOpacity(_ progress: CGFloat) -> CGFloat {
        clamp(1 - progress / openThreshold)
    }

    /// The details screen fades in over the last 70%.
    static func detailsOpacity(_ progress: CGFloat) -> CGFloat {
        clamp((progress - openThreshold) / (1 - openThreshold))
    }

    /// From the bar's corner radius at 0 to square corners at 1.
    static func cornerRadius(from start: CGFloat, progress: CGFloat) -> CGFloat {
        lerp(start, 0, clamp(progress))
    }

    static func lerp(_ from: CGFloat, _ to: CGFloat, _ fraction: CGFloat) -> CGFloat {
        from + (to - from) * fraction
    }

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}
