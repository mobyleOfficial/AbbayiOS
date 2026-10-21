//
//  ChapterCountViewTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Covers the 0-based-index to 1-based-display conversion that #104 moved out of the view
/// models and into the one view that renders a chapter counter.
final class ChapterCountViewTests: XCTestCase {
    private func display(_ index: Int, of total: Int) -> Int {
        ChapterCountView.displayNumber(forIndex: index, total: total)
    }

    func test_firstChapterDisplaysAsOne() {
        XCTAssertEqual(display(0, of: 3), 1, "a three-chapter book at the start reads 1/3, not 0/3")
    }

    func test_lastChapterDisplaysAsTotal() {
        XCTAssertEqual(display(2, of: 3), 3)
    }

    func test_noChaptersDisplaysZeroRatherThanOne() {
        XCTAssertEqual(display(0, of: 0), 0, "a book with no chapter metadata reads 0/0, not 1/0")
    }

    /// `AudioModel.currentChapter(for:)` falls back to index 0 and can report an index past the
    /// end (#101), so the conversion clamps rather than rendering something impossible.
    func test_indexPastTheEndIsClampedToTotal() {
        XCTAssertEqual(display(7, of: 3), 3, "must not render 8/3")
    }

    func test_negativeIndexDoesNotUnderflowBelowOne() {
        XCTAssertEqual(display(-1, of: 3), 0)
    }
}
