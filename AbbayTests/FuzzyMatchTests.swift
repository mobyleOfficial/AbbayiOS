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

    func test_scoreDiscrimination_exactBeatsPrefixBeatsContains() {
        // Library has one of each scoring tier for query "harry":
        //   "Old Harry Tales"      → contains "harry" but not prefix → 1
        //   "Harry"                → exact match after normalize     → 3
        //   "Harry the Adventurer" → hasPrefix "harry"               → 2
        // Exercises the comparator's score tier in a multi-entry library so a
        // future `<`→`>` flip can't silently pass.
        let library = [
            audio(title: "Old Harry Tales", url: "file:///a"),
            audio(title: "Harry", url: "file:///b"),
            audio(title: "Harry the Adventurer", url: "file:///c")
        ]
        let result = fuzzyMatch(input: "harry", audios: library, lastPlayedURL: nil)
        XCTAssertEqual(result?.url, URL(string: "file:///b"),
                       "exact match (score 3) must beat prefix (2) and contains (1)")
    }

    func test_scoreBeatsLastPlayed_whenScoresDiffer() {
        // "Book One" is last-played but only contains "book" (score 1).
        // "book" is an exact match (score 3) and NOT last-played.
        // Score must win over last-played status; protects against a reorder
        // bug that checks `isLastPlayed` before `score`.
        let library = [
            audio(title: "Book One", url: "file:///a"),
            audio(title: "book", url: "file:///b")
        ]
        let result = fuzzyMatch(input: "book", audios: library,
                                lastPlayedURL: URL(string: "file:///a"))
        XCTAssertEqual(result?.url, URL(string: "file:///b"),
                       "higher score must win even when a lower-scored entry is last-played")
    }
}
