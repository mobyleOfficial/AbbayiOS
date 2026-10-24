//
//  CoverTintTests.swift
//  AbbayTests
//

@testable import Abbay
import UIKit
import XCTest

/// The bar's background comes from the book's cover: an average of a tiny downscale, darkened
/// until white text on it passes 4.5:1. No artwork falls back to `onyx`.
final class CoverTintTests: XCTestCase {
    // MARK: - Helpers

    private func png(_ color: UIColor, side: CGFloat = 4) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private struct RGB {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
    }

    private func rgb(_ color: UIColor) -> RGB {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return RGB(red: red, green: green, blue: blue)
    }

    /// WCAG relative luminance, computed here independently of the implementation.
    private func contrastAgainstWhite(_ color: UIColor) -> CGFloat {
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let value = rgb(color)
        let luminance = 0.2126 * linear(value.red) + 0.7152 * linear(value.green) + 0.0722 * linear(value.blue)
        return 1.05 / (luminance + 0.05)
    }

    // MARK: - Tests

    func test_tint_withoutArtwork_isOnyx() {
        let onyx = rgb(ColorConstants.onyx.uiColor)

        let tint = rgb(CoverTint.color(for: nil))
        let garbage = rgb(CoverTint.color(for: Data([1, 2, 3])))

        for (value, expected) in [(tint.red, onyx.red), (tint.green, onyx.green), (tint.blue, onyx.blue)] {
            XCTAssertEqual(value, expected, accuracy: 0.001)
        }
        for (value, expected) in [(garbage.red, onyx.red), (garbage.green, onyx.green), (garbage.blue, onyx.blue)] {
            XCTAssertEqual(value, expected, accuracy: 0.001, "undecodable data falls back to onyx")
        }
    }

    func test_tint_forWhiteArtwork_isDarkEnoughForWhiteText() {
        let tint = CoverTint.color(for: png(.white))

        XCTAssertGreaterThanOrEqual(contrastAgainstWhite(tint), 4.5)
    }

    func test_tint_forDarkArtwork_isUnchangedRoughly() {
        let dark = UIColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 1)

        let tint = rgb(CoverTint.color(for: png(dark)))

        XCTAssertEqual(tint.red, 0.10, accuracy: 0.02)
        XCTAssertEqual(tint.green, 0.12, accuracy: 0.02)
        XCTAssertEqual(tint.blue, 0.20, accuracy: 0.02)
    }

    /// A large cover is reduced before averaging; a two-colour image averages to the middle.
    func test_tint_averagesTheArtwork() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format)
        let data = renderer.pngData { context in
            UIColor(red: 0.2, green: 0, blue: 0, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
            UIColor(red: 0, green: 0, blue: 0.2, alpha: 1).setFill()
            context.fill(CGRect(x: 100, y: 0, width: 100, height: 200))
        }

        let tint = rgb(CoverTint.color(for: data))

        XCTAssertEqual(tint.red, 0.1, accuracy: 0.02)
        XCTAssertEqual(tint.green, 0, accuracy: 0.02)
        XCTAssertEqual(tint.blue, 0.1, accuracy: 0.02)
    }

    /// Computed once per book: the same URL with different artwork still gets the first tint.
    func test_tint_isCachedPerBook() {
        let url = URL(string: "file:///tint/\(UUID().uuidString).m4b")
        let dark = UIColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 1)
        let first = AudioModel(title: "Dark", imageData: png(dark), url: url)
        let sameURL = AudioModel(title: "Dark", imageData: png(.white), url: url)

        let cached = rgb(CoverTint.cached(for: first))
        let again = rgb(CoverTint.cached(for: sameURL))

        XCTAssertEqual(cached.red, again.red, accuracy: 0.0001)
        XCTAssertEqual(cached.green, again.green, accuracy: 0.0001)
        XCTAssertEqual(cached.blue, again.blue, accuracy: 0.0001)
        XCTAssertEqual(again.blue, 0.20, accuracy: 0.02, "the second call computed a new tint")
    }
}
