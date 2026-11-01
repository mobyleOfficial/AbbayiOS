//
//  SettingsViewExperimentalTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Settings › Experimental shows only where Read-along can run, and not to VoiceOver users (owner:
/// "the audio would be playing together with the text which is already highlighted, do not show
/// this experimental toggle for voice over users"). XCUITest can't turn VoiceOver on, so the rule
/// is tested here.
final class SettingsViewExperimentalTests: XCTestCase {
    func test_available_voiceOverOff_isShown() {
        XCTAssertTrue(SettingsView.showsExperimental(isAvailable: true, voiceOverOn: false))
    }

    func test_available_voiceOverOn_isHidden() {
        XCTAssertFalse(SettingsView.showsExperimental(isAvailable: true, voiceOverOn: true))
    }

    func test_unavailable_isHidden() {
        XCTAssertFalse(SettingsView.showsExperimental(isAvailable: false, voiceOverOn: false))
        XCTAssertFalse(SettingsView.showsExperimental(isAvailable: false, voiceOverOn: true))
    }

    /// *Find chapters* stays for VoiceOver users: found chapters help them as much as anyone.
    func test_findChapters_isShownWhereTheEngineRuns_withOrWithoutVoiceOver() {
        XCTAssertTrue(SettingsView.showsFindChapters(isAvailable: true))
        XCTAssertFalse(SettingsView.showsFindChapters(isAvailable: false))
    }
}
