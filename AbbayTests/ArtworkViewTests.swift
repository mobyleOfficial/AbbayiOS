//
//  ArtworkViewTests.swift
//  AbbayTests
//

@testable import Abbay
import SwiftUI
import XCTest

/// The decisions behind every cover (#166 G6): the radius by size, the placeholder by book kind,
/// and when the generic tile shows instead of artwork.
final class ArtworkViewTests: XCTestCase {
    // MARK: - Corner radius

    func test_cornerRadius_growsWithTheSide_andCapsAtFourteen() {
        XCTAssertEqual(ArtworkView.cornerRadius(forSide: 36), 4)
        XCTAssertEqual(ArtworkView.cornerRadius(forSide: 48), 8)
        XCTAssertEqual(ArtworkView.cornerRadius(forSide: 64), 8)
        XCTAssertEqual(ArtworkView.cornerRadius(forSide: 150), 12)
        XCTAssertEqual(ArtworkView.cornerRadius(forSide: 288), 14)
        XCTAssertEqual(ArtworkView.cornerRadius(forSide: 1000), 14)
    }

    func test_cornerRadius_neverShrinksAsTheSideGrows() {
        let radii = stride(from: CGFloat(0), through: 400, by: 1).map(ArtworkView.cornerRadius(forSide:))
        XCTAssertEqual(radii, radii.sorted())
    }

    func test_shape_usesTheFixedRadius_whenGiven() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 300)
        let fixed = ArtworkShape(fixedRadius: 32).path(in: rect)
        let expected = RoundedRectangle(cornerRadius: 32, style: .continuous).path(in: rect)
        XCTAssertEqual(fixed.description, expected.description)
    }

    func test_shape_followsTheSize_withoutAFixedRadius() {
        let rect = CGRect(x: 0, y: 0, width: 48, height: 48)
        let sized = ArtworkShape().path(in: rect)
        let expected = RoundedRectangle(cornerRadius: 8, style: .continuous).path(in: rect)
        XCTAssertEqual(sized.description, expected.description)
    }

    // MARK: - Placeholder

    func test_placeholder_isABookForLibriVox_andHeadphonesForAnImport() {
        var book = AudioModel(title: "t", albumName: "", artist: "", duration: 1, chapters: [])
        XCTAssertEqual(ArtworkView.placeholder(for: book), .audio)
        XCTAssertEqual(ArtworkView.Placeholder.audio.systemImage, "headphones")

        book.librivoxID = "123"
        XCTAssertEqual(ArtworkView.placeholder(for: book), .book)
        XCTAssertEqual(ArtworkView.Placeholder.book.systemImage, "book.closed")
    }

    /// No artwork, or bytes that aren't an image, show the generic tile; a real image shows.
    func test_image_isNilWithoutDecodableData() throws {
        XCTAssertNil(ArtworkView.image(from: nil))
        XCTAssertNil(ArtworkView.image(from: Data("not an image".utf8)))

        let png = try XCTUnwrap(
            UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }.pngData()
        )
        XCTAssertNotNil(ArtworkView.image(from: png))
    }

    /// The same cover is decoded once: re-rendering (every frame of the player's expansion) gets
    /// the cached image back, even from a different `Data` with the same bytes (#254).
    func test_image_isDecodedOnceAndReused() throws {
        let png = try XCTUnwrap(
            UIGraphicsImageRenderer(size: CGSize(width: 3, height: 5)).image { context in
                UIColor.blue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 3, height: 5))
            }.pngData()
        )
        ArtworkView.decoded.removeAllObjects()
        let first = try XCTUnwrap(ArtworkView.image(from: png))
        let again = try XCTUnwrap(ArtworkView.image(from: Data(png)))
        XCTAssertTrue(first === again)
        XCTAssertNotNil(ArtworkView.decoded.object(forKey: png as NSData))
    }
}
