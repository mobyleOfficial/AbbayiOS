//
//  FuzzyMatchTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class FuzzyMatchTests: XCTestCase {

    private func audio(title: String, url: String) -> AudioModel {
        var m = AudioModel()
        m.title = title
        m.url = URL(string: url)
        return m
    }

    func test_exactMatch_afterNormalize_scoresHighest() {
        let library = [audio(title: "Harry Potter", url: "file:///a")]
        let result = fuzzyMatch(input: "harry potter", audios: library, lastPlayedURL: nil)
        XCTAssertEqual(result?.title, "Harry Potter")
    }

    func test_prefixMatch_returnsBook() {
        let library = [audio(title: "Harry Potter and the Sorcerer's Stone", url: "file:///a")]
        let result = fuzzyMatch(input: "harry", audios: library, lastPlayedURL: nil)
        XCTAssertEqual(result?.title, "Harry Potter and the Sorcerer's Stone")
    }

    func test_containsMatch_returnsBook() {
        let library = [audio(title: "Harry Potter and the Sorcerer's Stone", url: "file:///a")]
        let result = fuzzyMatch(input: "sorcerer", audios: library, lastPlayedURL: nil)
        XCTAssertEqual(result?.title, "Harry Potter and the Sorcerer's Stone")
    }

    func test_ampersandNormalizesToAnd() {
        let library = [audio(title: "Harry Potter and the Philosophers Stone", url: "file:///a")]
        let result = fuzzyMatch(input: "Harry Potter & the Philosophers Stone",
                                audios: library, lastPlayedURL: nil)
        XCTAssertEqual(result?.title, "Harry Potter and the Philosophers Stone")
    }

    func test_ampersandWithoutSurroundingSpaces_stillNormalizesToAnd() {
        // Order is load-bearing: `&` → ` and ` must run BEFORE punctuation stripping.
        // Reversed order would yield "tomjerry" which contains nothing in "tom and jerry".
        let library = [audio(title: "Tom and Jerry", url: "file:///a")]
        let result = fuzzyMatch(input: "Tom&Jerry", audios: library, lastPlayedURL: nil)
        XCTAssertEqual(result?.title, "Tom and Jerry")
    }

    func test_apostropheIsStripped_bothSides() {
        let library = [audio(title: "Dont Look Up", url: "file:///a")]
        let result = fuzzyMatch(input: "Don't Look Up", audios: library, lastPlayedURL: nil)
        XCTAssertEqual(result?.title, "Dont Look Up")
    }

    func test_lastPlayedWinsTie() {
        let a = audio(title: "Book One", url: "file:///a")
        let b = audio(title: "Book Two", url: "file:///b")
        // Both contain "book" → tie at score 1; b is last-played.
        let result = fuzzyMatch(input: "book", audios: [a, b],
                                lastPlayedURL: URL(string: "file:///b"))
        XCTAssertEqual(result?.url, URL(string: "file:///b"))
    }

    func test_libraryIndexAscendingTiebreak_whenNoLastPlayed() {
        // Both contain "book" → tie at score 1; neither last-played.
        // Library-order ascending wins → first entry.
        let a = audio(title: "Book One", url: "file:///a")
        let b = audio(title: "Book Two", url: "file:///b")
        let result = fuzzyMatch(input: "book", audios: [a, b], lastPlayedURL: nil)
        XCTAssertEqual(result?.url, URL(string: "file:///a"))
    }

    func test_noMatch_returnsNil() {
        let library = [audio(title: "Harry Potter", url: "file:///a")]
        XCTAssertNil(fuzzyMatch(input: "xyz", audios: library, lastPlayedURL: nil))
    }

    func test_emptyInput_returnsNil() {
        let library = [audio(title: "Harry Potter", url: "file:///a")]
        XCTAssertNil(fuzzyMatch(input: "", audios: library, lastPlayedURL: nil))
    }
}
