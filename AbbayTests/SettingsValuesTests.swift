//
//  SettingsValuesTests.swift
//  AbbayTests
//

@testable import Abbay
import UIKit
import XCTest

/// The value types behind the settings: speed steps and labels (ported from the Android app's
/// `SpeedSteps`), skip intervals and their SF Symbols, and the language codes.
final class SettingsValuesTests: XCTestCase {
    // MARK: - Speed

    func test_speedRangeAndPresets_matchAndroid() {
        XCTAssertEqual(PlaybackSpeed.minimum, 0.5)
        XCTAssertEqual(PlaybackSpeed.maximum, 3.5)
        XCTAssertEqual(PlaybackSpeed.step, 0.05)
        XCTAssertEqual(PlaybackSpeed.presets, [0.8, 1, 1.2, 1.5, 1.75, 2, 2.5])
    }

    func test_snap_roundsToTheStep_withoutDrift() {
        XCTAssertEqual(PlaybackSpeed.snap(1.2000001), 1.2)
        XCTAssertEqual(PlaybackSpeed.snap(1.024), 1)
        XCTAssertEqual(PlaybackSpeed.snap(1.026), 1.05)
        XCTAssertEqual(PlaybackSpeed.snap(1 + 0.05 + 0.05 + 0.05), 1.15)
    }

    func test_snap_clampsToTheRange() {
        XCTAssertEqual(PlaybackSpeed.snap(0.1), 0.5)
        XCTAssertEqual(PlaybackSpeed.snap(9), 3.5)
        XCTAssertEqual(PlaybackSpeed.snap(.nan), 1, "a NaN rate is normal speed, not a crash")
    }

    func test_stepUpAndDown_stopAtTheEnds() {
        XCTAssertEqual(PlaybackSpeed.stepped(1, by: 1), 1.05)
        XCTAssertEqual(PlaybackSpeed.stepped(1, by: -1), 0.95)
        XCTAssertEqual(PlaybackSpeed.stepped(3.5, by: 1), 3.5)
        XCTAssertEqual(PlaybackSpeed.stepped(0.5, by: -1), 0.5)
    }

    /// CarPlay's rate button (#150) has no sheet: each tap moves to the next preset.
    func test_nextPreset_cyclesThroughThePresets() {
        XCTAssertEqual(PlaybackSpeed.nextPreset(after: 0.8), 1)
        XCTAssertEqual(PlaybackSpeed.nextPreset(after: 1), 1.2)
        XCTAssertEqual(PlaybackSpeed.nextPreset(after: 1.75), 2)
        XCTAssertEqual(PlaybackSpeed.nextPreset(after: 2.5), 0.8, "the fastest wraps to the slowest")
    }

    /// A speed set in the sheet sits between presets, or past them: the next tap goes to the first
    /// preset above it, and past the fastest it wraps.
    func test_nextPreset_fromASpeedBetweenPresets_goesToTheNextOneUp() {
        XCTAssertEqual(PlaybackSpeed.nextPreset(after: 1.05), 1.2)
        XCTAssertEqual(PlaybackSpeed.nextPreset(after: 0.5), 0.8)
        XCTAssertEqual(PlaybackSpeed.nextPreset(after: 3), 0.8)
        XCTAssertEqual(PlaybackSpeed.nextPreset(after: 1.2000001), 1.5, "drift doesn't count as a speed")
        XCTAssertEqual(PlaybackSpeed.nextPreset(after: .nan), 1.2, "NaN is normal speed")
    }

    func test_label_showsOneOrTwoDecimals() {
        let english = Locale(identifier: "en")
        XCTAssertEqual(PlaybackSpeed.label(1, locale: english), "1.0×")
        XCTAssertEqual(PlaybackSpeed.label(1.25, locale: english), "1.25×")
        XCTAssertEqual(PlaybackSpeed.label(0.8, locale: english), "0.8×")
    }

    func test_label_inPortuguese_usesADecimalComma() {
        XCTAssertEqual(PlaybackSpeed.label(1.5, locale: Locale(identifier: "pt-BR")), "1,5×")
    }

    // MARK: - Skip intervals

    func test_skipIntervals_offerTheFourAmounts() {
        XCTAssertEqual(SkipInterval.allCases.map(\.rawValue), [10, 15, 30, 45])
        XCTAssertEqual(SkipInterval.thirty.seconds, 30)
    }

    /// Each amount has a matching SF Symbol, so the in-app buttons show the number they skip.
    func test_skipIntervals_mapToMatchingSymbols() {
        for interval in SkipInterval.allCases {
            XCTAssertEqual(interval.backwardSymbol, "gobackward.\(interval.rawValue)")
            XCTAssertEqual(interval.forwardSymbol, "goforward.\(interval.rawValue)")
            XCTAssertNotNil(UIImage(systemName: interval.backwardSymbol), interval.backwardSymbol)
            XCTAssertNotNil(UIImage(systemName: interval.forwardSymbol), interval.forwardSymbol)
        }
    }

    // MARK: - Language

    func test_languages_mapToTheirLprojCodes() {
        XCTAssertNil(AppLanguage.system.languageCode)
        XCTAssertEqual(AppLanguage.english.languageCode, "en")
        XCTAssertEqual(AppLanguage.portuguese.languageCode, "pt-BR")
    }

    // MARK: - About the developer

    func test_linkedInURL_isTheDevelopersHTTPSProfile() {
        XCTAssertEqual(SettingsView.linkedInURL?.absoluteString, "https://www.linkedin.com/in/edyuto")
        XCTAssertEqual(SettingsView.linkedInURL?.scheme, "https")
    }
}
