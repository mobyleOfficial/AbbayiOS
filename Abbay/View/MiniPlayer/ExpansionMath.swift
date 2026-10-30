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

    /// A flick of at least 800 pt/s settles in its own direction, even against the drag's (#130):
    /// up opens, down closes. Slower, the distance decides: opening past 30%; closing is the
    /// mirror, it stays open only while above 70%.
    static func shouldOpen(progress: CGFloat, velocityY: CGFloat, wasOpening: Bool) -> Bool {
        if velocityY <= -flickVelocity { return true }
        if velocityY >= flickVelocity { return false }
        return wasOpening ? progress >= openThreshold : progress > 1 - openThreshold
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

    // MARK: - Origin (#241)

    /// Where an open grows from, or a close lands: the tapped cover (a library cell or the Continue
    /// card) while it is still on screen, else the mini player bar while it is visible, else the
    /// bottom strip. `cover` and `bar` are global frames; `bar` is nil when no bar is visible.
    static func origin(cover: ExpansionCover?, bar: CGRect?, screen: CGSize) -> ExpansionOrigin {
        if let cover, isOnScreen(cover.frame, screen: screen) { return .cover(cover) }
        if let bar { return .bar(bar) }
        return .bottomStrip
    }

    /// A cover counts as on screen when at least half of it is inside the window: a cell scrolled
    /// mostly out of view, or one that is gone (an empty frame), is not somewhere to land.
    static func isOnScreen(_ frame: CGRect, screen: CGSize) -> Bool {
        guard frame.width > 0, frame.height > 0, screen.width > 0, screen.height > 0 else { return false }
        let visible = frame.intersection(CGRect(origin: .zero, size: screen))
        guard !visible.isNull else { return false }
        return visible.width * visible.height >= frame.width * frame.height / 2
    }

    /// The distance a drag covers for 0…1: from the start frame's top to the screen's top, but at
    /// least half the screen, so a collapse toward a cover near the top isn't hair-trigger.
    static func travel(startFrame: CGRect, screen: CGSize) -> CGFloat {
        max(startFrame.minY, screen.height / 2)
    }

    /// The growing cover's slot at progress 0, in the start frame's coordinates: the bar's cover
    /// slot, or the whole frame when the expansion starts from a cover.
    static func coverSlot(origin: ExpansionOrigin, startFrame: CGRect, barSlot: CGRect) -> CGRect {
        if case .cover = origin { return CGRect(origin: .zero, size: startFrame.size) }
        return barSlot
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

    // MARK: - Appearance

    /// The panel at `progress`: everything `ExpansionLayout` draws that depends on the progress.
    /// With `reduceMotion` the panel is full-screen with square corners at every progress, the
    /// bar's face is gone and the details screen fully drawn, and only `panelOpacity` moves (the
    /// cross-fade). Otherwise the frame and corners interpolate from the bar and the panel stays
    /// opaque.
    static func appearance(
        progress: CGFloat,
        startFrame: CGRect,
        screen: CGSize,
        startRadius: CGFloat,
        reduceMotion: Bool
    ) -> ExpansionAppearance {
        let fraction = clamp(progress)
        let full = CGRect(origin: .zero, size: screen)
        if reduceMotion {
            return ExpansionAppearance(
                panelFrame: full,
                cornerRadius: 0,
                panelOpacity: fraction,
                barContentOpacity: 0,
                detailsOpacity: 1
            )
        }
        return ExpansionAppearance(
            panelFrame: interpolate(startFrame, full, fraction),
            cornerRadius: cornerRadius(from: startRadius, progress: fraction),
            panelOpacity: 1,
            barContentOpacity: barContentOpacity(fraction),
            detailsOpacity: detailsOpacity(fraction)
        )
    }

    /// The growing cover's frame on screen at `progress`: from the bar's cover slot (`barSlot`, in
    /// the start frame's coordinates) to `target` (where the details screen lays it out), riding
    /// with the panel's top edge. With `reduceMotion` it is `target` at every progress.
    static func coverFrame(
        progress: CGFloat,
        barSlot: CGRect,
        target: CGRect,
        panelFrame: CGRect,
        reduceMotion: Bool
    ) -> CGRect {
        if reduceMotion { return target }
        let toSlot = target.offsetBy(dx: -panelFrame.minX, dy: 0)
        return interpolate(barSlot, toSlot, clamp(progress)).offsetBy(dx: panelFrame.minX, dy: panelFrame.minY)
    }

    /// The growing cover's corner radius: from the bar's to the details screen's, or the details
    /// screen's at every progress with `reduceMotion`.
    static func coverRadius(progress: CGFloat, from start: CGFloat, to end: CGFloat, reduceMotion: Bool) -> CGFloat {
        reduceMotion ? end : lerp(start, end, clamp(progress))
    }

    /// With the read-along text in the square (#192), how far the growing cover has turned from the
    /// artwork (0) into the text square's dark fill (1): eased over the growth, from 10% to 90%, so
    /// it lands as the square it hands over to and leaves the bar as the artwork, with no swap at
    /// either end (owner's device test). With `reduceMotion` nothing grows, so it is the square
    /// throughout and only the panel's fade shows.
    static func textSquareBlend(progress: CGFloat, reduceMotion: Bool) -> CGFloat {
        if reduceMotion { return 1 }
        let fraction = clamp((progress - 0.1) / 0.8)
        return fraction * fraction * (3 - 2 * fraction)
    }

    static func lerp(_ from: CGFloat, _ to: CGFloat, _ fraction: CGFloat) -> CGFloat {
        from + (to - from) * fraction
    }

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

/// A tapped cover the expansion can grow from: its global frame and its corner radius.
struct ExpansionCover: Equatable {
    let frame: CGRect
    let cornerRadius: CGFloat
}

/// Where the expansion grows from and collapses back to (#241).
enum ExpansionOrigin: Equatable {
    /// The 56 pt strip along the bottom edge: no bar is visible.
    case bottomStrip
    /// The mini player bar's global frame.
    case bar(CGRect)
    /// A tapped cover: a library cell's or the Continue card's.
    case cover(ExpansionCover)

    /// The start frame, or nil for the bottom strip (`ExpansionMath.startFrame` fills it in).
    var frame: CGRect? {
        switch self {
        case .bottomStrip: nil
        case let .bar(frame): frame
        case let .cover(cover): cover.frame
        }
    }

    var isBar: Bool {
        if case .bar = self { return true }
        return false
    }

    /// The cover's corner radius, or nil for the bar and the strip.
    var coverRadius: CGFloat? {
        if case let .cover(cover) = self { return cover.cornerRadius }
        return nil
    }
}

/// What `ExpansionMath.appearance` decides for one progress value: the panel's frame (in screen
/// coordinates), its corner radius, its overall opacity, and the opacities of the bar's face and
/// the details screen inside it.
struct ExpansionAppearance: Equatable {
    let panelFrame: CGRect
    let cornerRadius: CGFloat
    let panelOpacity: CGFloat
    let barContentOpacity: CGFloat
    let detailsOpacity: CGFloat
}
