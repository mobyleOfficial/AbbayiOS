//
//  PlayButtonViewTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The play/pause glyph had no accessibility label, so VoiceOver read nothing and a UI test couldn't
/// tell Play from Pause (#115: after a failure the button must read Play).
final class PlayButtonViewTests: XCTestCase {
    func test_label_saysWhatATapDoes() {
        XCTAssertEqual(PlayButtonView.label(isPlaying: false), Localizable.play.localized)
        XCTAssertEqual(PlayButtonView.label(isPlaying: true), Localizable.pause.localized)
        XCTAssertNotEqual(PlayButtonView.label(isPlaying: false), PlayButtonView.label(isPlaying: true))
    }
}
