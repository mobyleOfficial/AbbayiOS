//
//  ContinueCardTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The library's Continue card (#166 G3): the last played book, if it is still in the library and
/// not finished.
final class ContinueCardTests: XCTestCase {
    private let lastURL = URL(fileURLWithPath: "/books/last.m4b")
    private let otherURL = URL(fileURLWithPath: "/books/other.m4b")

    private func book(_ url: URL, duration: Double = 400, currentTime: Double = 100) -> AudioModel {
        AudioModel(title: url.lastPathComponent, duration: duration, currentTime: currentTime, url: url)
    }

    func test_lastPlayedBookInTheLibrary_isShown() {
        let books = [book(otherURL), book(lastURL)]

        XCTAssertEqual(ContinueCard.book(in: books, lastPlayedURL: lastURL)?.url, lastURL)
    }

    func test_nothingPlayedYet_noCard() {
        XCTAssertNil(ContinueCard.book(in: [book(lastURL)], lastPlayedURL: nil))
    }

    /// Deleted since it was played, or never in this library.
    func test_lastPlayedBookNoLongerInTheLibrary_noCard() {
        XCTAssertNil(ContinueCard.book(in: [book(otherURL)], lastPlayedURL: lastURL))
    }

    /// Listened to the end, as Settings' *Delete finished downloads* counts it.
    func test_finishedLastPlayedBook_noCard() {
        let finished = book(lastURL, duration: 400, currentTime: 380)

        XCTAssertNil(ContinueCard.book(in: [finished], lastPlayedURL: lastURL))
    }

    /// A last played book that was never really started still gets its card: it is what the user
    /// picked last.
    func test_unstartedLastPlayedBook_isShown() {
        XCTAssertNotNil(ContinueCard.book(in: [book(lastURL, currentTime: 0)], lastPlayedURL: lastURL))
    }

    func test_progress_isClampedAndZeroWithoutADuration() {
        let started = book(lastURL, duration: 400)

        XCTAssertEqual(ContinueCard.progress(book: started, bookTime: 100), 0.25, accuracy: 0.001)
        XCTAssertEqual(ContinueCard.progress(book: started, bookTime: 900), 1)
        XCTAssertEqual(ContinueCard.progress(book: started, bookTime: -5), 0)
        XCTAssertEqual(ContinueCard.progress(book: AudioModel(url: lastURL), bookTime: 10), 0)
        XCTAssertEqual(ContinueCard.progress(book: started, bookTime: .nan), 0)
    }
}
