//
//  SleepTimerPillTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// What the moon pill says (#332): its menu's titles and what VoiceOver reads for it.
final class SleepTimerPillTests: XCTestCase {
    func test_accessibilityValue_off() {
        XCTAssertEqual(SleepTimerPill.accessibilityValue(choice: nil, remaining: nil), "Off")
    }

    func test_accessibilityValue_roundsMinutesUp() {
        XCTAssertEqual(SleepTimerPill.accessibilityValue(choice: .duration(900), remaining: 719), "12 minutes left")
        XCTAssertEqual(SleepTimerPill.accessibilityValue(choice: .duration(900), remaining: 61), "2 minutes left")
        XCTAssertEqual(SleepTimerPill.accessibilityValue(choice: .duration(900), remaining: 60), "1 minute left")
    }

    func test_accessibilityValue_underAMinute() {
        XCTAssertEqual(
            SleepTimerPill.accessibilityValue(choice: .duration(300), remaining: 59),
            "Less than a minute left"
        )
    }

    func test_accessibilityValue_endOfChapter() {
        XCTAssertEqual(
            SleepTimerPill.accessibilityValue(choice: .endOfChapter, remaining: nil),
            "When current chapter ends"
        )
    }

    func test_title_ofEachChoice() {
        XCTAssertEqual(SleepTimerPill.title(of: .duration(300)), "5 minutes")
        XCTAssertEqual(SleepTimerPill.title(of: .duration(2700)), "45 minutes")
        XCTAssertEqual(SleepTimerPill.title(of: .duration(3600)), "1 hour")
        XCTAssertEqual(SleepTimerPill.title(of: .endOfChapter), "When current chapter ends")
    }

    /// The countdown on the pill: minutes and seconds, hours when there are any.
    func test_countdown() {
        XCTAssertEqual(SleepTimerPill.countdown(754), "12:34")
        XCTAssertEqual(SleepTimerPill.countdown(3600), "60:00", "minutes only: the longest choice is an hour")
        XCTAssertEqual(SleepTimerPill.countdown(7.4), "0:08", "rounds up, so it never reads 0:00 while running")
    }
}
