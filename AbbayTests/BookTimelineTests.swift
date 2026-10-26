//
//  BookTimelineTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class BookTimelineTests: XCTestCase {
    private let timeline = BookTimeline(chapters: [
        ChapterModel(title: "A", startTime: 0, duration: 100),
        ChapterModel(title: "B", startTime: 100, duration: 50),
        ChapterModel(title: "C", startTime: 150, duration: 200)
    ])

    func test_position_atStart() {
        XCTAssertEqual(timeline.position(at: 0), .init(chapterIndex: 0, offset: 0))
    }

    func test_position_insideSecondChapter() {
        XCTAssertEqual(timeline.position(at: 120), .init(chapterIndex: 1, offset: 20))
    }

    func test_position_onBoundary_belongsToNextChapter() {
        XCTAssertEqual(timeline.position(at: 150), .init(chapterIndex: 2, offset: 0))
    }

    func test_position_negative_clampsToStart() {
        XCTAssertEqual(timeline.position(at: -5), .init(chapterIndex: 0, offset: 0))
    }

    func test_position_pastEnd_clampsToLastChapterEnd() {
        XCTAssertEqual(timeline.position(at: 999), .init(chapterIndex: 2, offset: 200))
    }

    func test_bookTime_addsChapterStart() {
        XCTAssertEqual(timeline.bookTime(chapterIndex: 2, offset: 10), 160)
    }

    func test_emptyChapters_positionPassesTimeThrough() {
        let empty = BookTimeline(chapters: [])
        XCTAssertEqual(empty.position(at: 5), .init(chapterIndex: 0, offset: 5))
    }
}
