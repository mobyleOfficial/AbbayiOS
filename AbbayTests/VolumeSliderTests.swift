//
//  VolumeSliderTests.swift
//  AbbayTests
//

@testable import Abbay
import SwiftUI
import XCTest

/// The volume capsule's placement over its pill, and VoiceOver's step on the pill and the capsule.
final class VolumeSliderTests: XCTestCase {
    private let screen = CGSize(width: 390, height: 700)

    // MARK: - Layout

    func test_capsule_sitsCentredJustAboveThePill() {
        let pill = CGRect(x: 100, y: 640, width: 50, height: 40)

        let frame = VolumeSliderLayout.frame(container: screen, pill: pill)

        XCTAssertEqual(frame.midX, pill.midX)
        XCTAssertEqual(frame.maxY, pill.minY - VolumeSliderLayout.gap)
        XCTAssertEqual(frame.width, VolumeSliderLayout.width)
        XCTAssertEqual(frame.height, VolumeSliderLayout.height)
    }

    /// A pill hard against the leading edge keeps the capsule on screen.
    func test_capsule_staysInsideTheScreensEdges() {
        let leading = VolumeSliderLayout.frame(container: screen, pill: CGRect(x: 0, y: 640, width: 20, height: 40))
        let trailing = VolumeSliderLayout.frame(container: screen, pill: CGRect(x: 380, y: 640, width: 20, height: 40))

        XCTAssertEqual(leading.minX, VolumeSliderLayout.gap)
        XCTAssertEqual(trailing.maxX, screen.width - VolumeSliderLayout.gap)
    }

    /// A phone in landscape: less room above the pill than the capsule asks for.
    func test_capsule_shrinksOnAShortScreen() {
        let pill = CGRect(x: 400, y: 120, width: 50, height: 40)

        let frame = VolumeSliderLayout.frame(container: CGSize(width: 800, height: 170), pill: pill)

        XCTAssertEqual(frame.minY, VolumeSliderLayout.gap)
        XCTAssertEqual(frame.maxY, 120 - VolumeSliderLayout.gap)
    }

    // MARK: - VoiceOver

    func test_voiceOverSwipe_movesTenPercent_andStopsAtTheEnds() {
        XCTAssertEqual(BookVolume.adjusted(0.5, .increment), 0.6)
        XCTAssertEqual(BookVolume.adjusted(0.5, .decrement), 0.4)
        XCTAssertEqual(BookVolume.adjusted(0.95, .increment), 1)
        XCTAssertNil(BookVolume.adjusted(1, .increment), "already full")
        XCTAssertNil(BookVolume.adjusted(0, .decrement), "already muted")
    }
}
