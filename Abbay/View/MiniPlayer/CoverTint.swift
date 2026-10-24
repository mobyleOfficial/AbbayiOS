//
//  CoverTint.swift
//  Abbay
//

import ImageIO
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

    private static let cache = NSCache<NSURL, UIColor>()

    /// Computed once per book, keyed by its URL. Books without a URL aren't cached.
    static func cached(for book: AudioModel) -> UIColor {
        guard let url = book.url as NSURL? else { return color(for: book.imageData) }
        if let color = cache.object(forKey: url) { return color }
        let color = color(for: book.imageData)
        cache.setObject(color, forKey: url)
        return color
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
