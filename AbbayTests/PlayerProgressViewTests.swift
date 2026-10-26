@testable import Abbay
import SwiftUI
import XCTest

/// The scrubber's fill stays inside the track's capsule. Near the start of a long book the fill is
/// under a point wide; drawn as a capsule of its own it was a 6 pt tall line standing outside the
/// track's rounded start.
@MainActor
final class PlayerProgressViewTests: XCTestCase {
    private let width: CGFloat = 300
    private let scale: CGFloat = 4

    func test_fillNearTheStart_staysInsideTheTracksRoundedEnd() throws {
        let image = try render(current: 125, total: 48_657)
        let track = try trackRows(in: image)
        // The track's top-left corner lies outside the capsule's rounded start: nothing bright there.
        XCTAssertLessThan(
            brightness(in: image, x: 0.4, y: track.lowerBound + 0.4),
            0.1,
            "the fill is drawn outside the track's rounded start"
        )
        // The middle of the left end is inside the capsule: the white fill shows there.
        XCTAssertGreaterThan(brightness(in: image, x: 0.4, y: (track.lowerBound + track.upperBound) / 2), 0.9)
    }

    func test_fillHalfway_isWhiteUpToTheMiddle_andTrackAfter() throws {
        let image = try render(current: 50, total: 100)
        let middle = try trackRows(in: image)
        let y = (middle.lowerBound + middle.upperBound) / 2
        XCTAssertGreaterThan(brightness(in: image, x: width * 0.25, y: y), 0.9)
        XCTAssertLessThan(brightness(in: image, x: width * 0.75, y: y), 0.5)
    }

    /// The track's vertical extent, in points: the rows that aren't black a quarter of the way in.
    private func trackRows(in image: CGImage) throws -> ClosedRange<CGFloat> {
        let height = CGFloat(image.height) / scale
        let rows = stride(from: 0, to: height, by: 1 / scale).filter {
            brightness(in: image, x: width * 0.25, y: $0) > 0.1
        }
        let first = try XCTUnwrap(rows.first, "no track found")
        let last = try XCTUnwrap(rows.last)
        return first...(last + 1 / scale)
    }

    // MARK: - Helpers

    /// Drawn through a hosting view in a window: `ImageRenderer` can't draw the scrubber's
    /// `GeometryReader` (it paints a placeholder).
    private func render(current: Double, total: Double) throws -> CGImage {
        let view = PlayerProgressView(currentTime: .constant(current), totalTime: total)
            .frame(width: width)
            .background(Color.black)
        let host = UIHostingController(rootView: view)
        host.safeAreaRegions = []
        let size = host.sizeThatFits(in: CGSize(width: width, height: 200))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        defer { window.isHidden = true }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrubber-\(Int(current))-of-\(Int(total)).png")
        try image.pngData()?.write(to: url)
        print("SNAPSHOT \(url.path)")
        return try XCTUnwrap(image.cgImage)
    }

    /// The brightness (0...1, the red channel over black) at a point, in the view's points.
    private func brightness(in image: CGImage, x: CGFloat, y: CGFloat) -> CGFloat {
        let px = Int(x * scale), py = Int(y * scale)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(image, in: CGRect(x: -px, y: py - image.height + 1, width: image.width, height: image.height))
        return CGFloat(pixel[0]) / 255
    }
}
