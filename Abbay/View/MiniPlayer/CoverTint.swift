//
//  CoverTint.swift
//  Abbay
//

import ImageIO
import SwiftUI
import UIKit

/// The mini player's background, derived from the book's cover: the average colour of a tiny
/// downscale, darkened until white text on it passes WCAG's 4.5:1. Without artwork (or with data
/// that isn't an image) it is `onyx`. The bar's text is always white.
enum CoverTint {
    /// The longest side the cover is reduced to before averaging.
    private static let sampleSide = 16
    private static let minimumContrast: CGFloat = 4.5
    /// Each darkening step multiplies the HSB brightness by this.
    private static let darkeningStep: CGFloat = 0.9

    /// Keyed by the book's URL, or by its artwork for a book without one. `NSCache` is thread-safe.
    private static let cache = NSCache<NSObject, UIColor>()

    /// What identifies a book's tint: its URL, else its artwork; nil when it has neither.
    private static func key(for book: AudioModel) -> NSObject? {
        if let url = book.url { return url as NSURL }
        return book.imageData.map { $0 as NSData }
    }

    /// The tint already computed for `book`, without computing anything: safe in a body. A book
    /// with neither a URL nor artwork is `onyx` at once. Nil until `tint(for:)` has run.
    static func cachedTint(for book: AudioModel) -> UIColor? {
        guard let key = key(for: book) else { return ColorConstants.onyx.uiColor }
        return cache.object(forKey: key)
    }

    /// Computed once per book, off the main thread (#130), and cached for `cachedTint(for:)`.
    static func tint(for book: AudioModel) async -> UIColor {
        if let cached = cachedTint(for: book) { return cached }
        let imageData = book.imageData
        let computed = await Task.detached(priority: .userInitiated) {
            Self.color(for: imageData)
        }.value
        guard let key = key(for: book) else { return computed }
        // Two callers can race (the bar and the expanding panel): the first tint stored wins.
        if let stored = cache.object(forKey: key) { return stored }
        cache.setObject(computed, forKey: key)
        return computed
    }

    static func color(for imageData: Data?) -> UIColor {
        guard let imageData, let average = averageColor(of: imageData) else {
            return ColorConstants.onyx.uiColor
        }
        return darkenedForWhiteText(average)
    }

    // MARK: - Averaging

    /// Decodes straight to a thumbnail (ImageIO never decodes the full cover), draws it into an
    /// sRGB bitmap and averages its pixels.
    private static func averageColor(of data: Data) -> UIColor? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: sampleSide,
                  kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let width = min(image.width, sampleSide)
        let height = min(image.height, sampleSide)
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var red = 0, green = 0, blue = 0, alpha = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            red += Int(pixels[index])
            green += Int(pixels[index + 1])
            blue += Int(pixels[index + 2])
            alpha += Int(pixels[index + 3])
        }
        // Premultiplied: dividing by the total alpha un-premultiplies the average.
        guard alpha > 0 else { return nil }
        let total = CGFloat(alpha)
        return UIColor(
            red: CGFloat(red) / total,
            green: CGFloat(green) / total,
            blue: CGFloat(blue) / total,
            alpha: 1
        )
    }

    // MARK: - Contrast

    private static func darkenedForWhiteText(_ color: UIColor) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return ColorConstants.onyx.uiColor
        }
        var candidate = color
        // Bounded: brightness 1 reaches black-enough well within 40 steps (0.9^40 ≈ 0.015).
        for _ in 0..<40 where contrastAgainstWhite(candidate) < minimumContrast {
            brightness *= darkeningStep
            candidate = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        }
        return candidate
    }

    /// WCAG 2 contrast ratio of white over `color`.
    static func contrastAgainstWhite(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return 1.05 / (luminance + 0.05)
    }
}

// MARK: - Background

/// A background in the book's cover tint: the bar's, and the expanding panel's while it still
/// looks like the bar. The body only looks the tint up; the first time for a book it is computed
/// off the main thread, and until then (a frame or two) the background is `onyx`, the no-artwork
/// tint. A book seen before gets its tint on the first frame.
///
/// A modifier, not a view, so the background stays a plain `Color`: in the system tab bar's
/// accessory (iOS 26.1+) a `Color` background blends with the glass, while a `Color` wrapped in a
/// view carrying `.task` drew visibly darker (#141's screenshots).
struct CoverTintBackground: ViewModifier {
    let book: AudioModel

    @State
    private var resolved: (identity: Identity, color: UIColor)?

    /// Which tint the book has: its URL's, else its artwork's (as `CoverTint` keys its cache).
    private enum Identity: Equatable {
        case url(URL)
        case artwork(Data?)

        init(_ book: AudioModel) {
            self = book.url.map(Identity.url) ?? .artwork(book.imageData)
        }
    }

    func body(content: Content) -> some View {
        let identity = Identity(book)
        let color = resolved.flatMap { $0.identity == identity ? $0.color : nil }
            ?? CoverTint.cachedTint(for: book)
            ?? ColorConstants.onyx.uiColor
        content
            .background(Color(uiColor: color))
            .task(id: identity) {
                let tint = await CoverTint.tint(for: book)
                resolved = (identity, tint)
            }
    }
}
