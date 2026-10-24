//
//  AudioModelTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// `AudioModel.currentChapter(for:)` on synthetic chapters (#101). The real boundaries of the
/// fixture are covered in `FileLoaderTests`.
final class AudioModelTests: XCTestCase {
    private func chaptered() -> AudioModel {
        AudioModel(
            duration: 300,
            chapters: [
                ChapterModel(title: "one", startTime: 0, duration: 100),
                ChapterModel(title: "two", startTime: 100, duration: 100),
                ChapterModel(title: "three", startTime: 200, duration: 100)
            ]
        )
    }

    func test_currentChapter_atAChaptersStart_isThatChapter() {
        XCTAssertEqual(chaptered().currentChapter(for: 100), 1)
        XCTAssertEqual(chaptered().currentChapter(for: 200), 2)
    }

    func test_currentChapter_justBeforeABoundary_isStillThePreviousChapter() {
        XCTAssertEqual(chaptered().currentChapter(for: 99.5), 0, "no early hand-off to the next chapter")
        XCTAssertEqual(chaptered().currentChapter(for: 199.9), 1)
    }

    func test_currentChapter_atOrPastTheEnd_isTheLastChapter() {
        XCTAssertEqual(chaptered().currentChapter(for: 299.9), 2)
        XCTAssertEqual(chaptered().currentChapter(for: 300), 2)
        XCTAssertEqual(chaptered().currentChapter(for: 10_000), 2, "must clamp, not wrap to the first chapter")
    }

    func test_currentChapter_beforeTheFirstChapter_isTheFirstChapter() {
        XCTAssertEqual(chaptered().currentChapter(for: -5), 0)
    }

    func test_currentChapter_noChapters_isNil() {
        XCTAssertNil(AudioModel().currentChapter(for: 0), "no chapter must not read as chapter 0")
        XCTAssertNil(AudioModel().currentChapter(for: 50))
    }

    func test_currentChapter_nonFiniteTime_isNil() {
        XCTAssertNil(chaptered().currentChapter(for: .nan))
    }
}
