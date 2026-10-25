//
//  SpokenChapterMatchingTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// `matchChapters` against what people say to Siri for a chapter (#206): a position as digits or
/// words, or the chapter's title with extra words, in en and pt-BR. `ChapterEntityQuery` (the
/// "Play \<chapter> in Abbay" App Shortcut) matches through it.
final class SpokenChapterMatchingTests: XCTestCase {
    private struct Case {
        let query: String
        /// One-based chapter positions, best first.
        let expected: [Int]
        let line: UInt

        init(_ query: String, _ expected: [Int], line: UInt = #line) {
            self.query = query
            self.expected = expected
            self.line = line
        }
    }

    private func check(_ cases: [Case], in titles: [String]) {
        for testCase in cases {
            let found = matchChapters(input: testCase.query, titles: titles).map { $0 + 1 }
            let described = found.map { titles[$0 - 1] }
            XCTAssertEqual(found, testCase.expected, "\"\(testCase.query)\" found \(described)", line: testCase.line)
        }
    }

    /// Titles with words, as in a LibriVox book or an m4b's own chapters.
    private let english = [
        "Prologue",
        "The Boy Who Lived",
        "The Vanishing Glass",
        "The Letters from No One",
        "Diagon Alley",
        "Chapter 6: The Journey",
        "Epilogue"
    ]

    private let portuguese = [
        "Prólogo",
        "Do título",
        "Do livro",
        "A Lição de Botânica",
        "O Quarto",
        "Capítulo Final",
        "Epílogo"
    ]

    /// Titles that are only numbers, as most files without named chapters have.
    private let numbered = (1...25).map { "Chapter \($0)" }

    func test_english_positions_spokenAsDigitsOrWords() {
        let cases: [Case] = [
            Case("4", [4]),
            Case("chapter 4", [4]),
            Case("Chapter 4", [4]),
            Case("chapter four", [4]),
            Case("the fourth chapter", [4]),
            Case("4th chapter", [4]),
            Case("chapter number 3", [3]),
            Case("chapter one", [1]),
            Case("first chapter", [1]),
            Case("chapter seven", [7]),
            // A number that isn't a word of any title, alone.
            Case("five", [5])
        ]
        check(cases, in: english)
    }

    func test_english_twoWordNumbers() {
        let cases: [Case] = [
            Case("chapter twenty one", [21]),
            Case("chapter twenty-one", [21]),
            Case("the twenty first chapter", [21]),
            Case("chapter 21", [21]),
            Case("21st chapter", [21]),
            Case("chapter twelve", [12]),
            Case("twentieth chapter", [20])
        ]
        check(cases, in: numbered)
    }

    func test_english_titles_withExtraWords() {
        let cases: [Case] = [
            Case("prologue", [1]),
            Case("the prologue", [1]),
            Case("the prologue chapter", [1]),
            Case("chapter prologue", [1]),
            Case("PROLOGUE", [1]),
            Case("the boy who lived", [2]),
            Case("boy who lived", [2]),
            Case("the vanishing glass chapter", [3]),
            Case("vanishing glass", [3]),
            Case("the letters from no one", [4]),
            Case("diagon alley", [5]),
            Case("the journey", [6]),
            Case("chapter 6 the journey", [6]),
            Case("epilogue", [7]),
            Case("glass vanishing", [3])
        ]
        check(cases, in: english)
    }

    func test_english_negatives() {
        let cases: [Case] = [
            Case("the", []),
            Case("a", []),
            Case("of the", []),
            Case("chapter", []),
            Case("the chapter", []),
            Case("chapter 9", []),
            Case("chapter nine", []),
            Case("0", []),
            Case("chapter zero", []),
            Case("the half blood prince", []),
            Case("pro", []),
            Case("van", []),
            Case("forty two", [])
        ]
        check(cases, in: english)
        check([Case("chapter 26", []), Case("chapter ninety nine", [])], in: numbered)
    }

    func test_portuguese_positions_spokenAsDigitsOrWords() {
        let cases: [Case] = [
            Case("capítulo 3", [3]),
            Case("capitulo 3", [3]),
            Case("o capítulo 3", [3]),
            Case("capítulo três", [3]),
            Case("capitulo tres", [3]),
            Case("o terceiro capítulo", [3]),
            Case("capítulo um", [1]),
            Case("primeiro capítulo", [1]),
            Case("a primeira", [1]),
            Case("capítulo número 2", [2]),
            Case("3º capítulo", [3]),
            Case("capítulo sete", [7]),
            Case("cinco", [5])
        ]
        check(cases, in: portuguese)
    }

    func test_portuguese_twoWordNumbers() {
        let cases: [Case] = [
            Case("capítulo vinte e um", [21]),
            Case("capítulo vinte e dois", [22]),
            Case("vigésimo primeiro capítulo", [21]),
            Case("décimo primeiro capítulo", [11]),
            Case("capítulo onze", [11]),
            Case("capítulo dezesseis", [16]),
            Case("capítulo 25", [25])
        ]
        check(cases, in: numbered)
    }

    func test_portuguese_titles_withExtraWords() {
        let cases: [Case] = [
            Case("prólogo", [1]),
            Case("prologo", [1]),
            Case("o prólogo", [1]),
            Case("o capítulo prólogo", [1]),
            Case("capítulo do prólogo", [1]),
            Case("a lição de botânica", [4]),
            Case("licao de botanica", [4]),
            Case("lição de botânica capítulo", [4]),
            // A title that is a number word: the title wins when "capítulo" isn't said…
            Case("o quarto", [5]),
            Case("quarto", [5]),
            // …and the position when it is.
            Case("o quarto capítulo", [4]),
            Case("capítulo final", [6]),
            Case("epílogo", [7]),
            Case("do livro", [3])
        ]
        check(cases, in: portuguese)
    }

    func test_portuguese_negatives() {
        let cases: [Case] = [
            Case("o", []),
            Case("a", []),
            Case("de", []),
            Case("do", []),
            Case("capítulo", []),
            Case("o capítulo", []),
            Case("capítulo 9", []),
            Case("capítulo nove", []),
            Case("dom casmurro", []),
            Case("pró", []),
            Case("quarenta e dois", [])
        ]
        check(cases, in: portuguese)
    }

    /// Several chapters share the words: all of them, in book order.
    func test_tiedTitles_areAllReturned_inBookOrder() {
        let titles = ["Part One: Arrival", "Interlude", "Part Two: Arrival"]
        check([Case("arrival", [1, 3]), Case("interlude", [2])], in: titles)
    }

    /// A number past the book, said on its own, can still be a title.
    func test_aNumberPastTheBook_fallsThroughToTheTitles() {
        let titles = ["Opening", "1984", "Closing"]
        check([Case("1984", [2]), Case("2", [2]), Case("chapter 3", [3])], in: titles)
    }

    /// The only number in a request the titles don't explain is still the position.
    func test_aLoneNumberAmongOtherWords_isThePosition() {
        check([Case("play chapter 4 please", [4]), Case("toca o capítulo 2 agora", [2])], in: english)
    }

    func test_emptyInputOrBook_matchesNothing() {
        XCTAssertEqual(matchChapters(input: "", titles: english), [])
        XCTAssertEqual(matchChapters(input: "   ", titles: english), [])
        XCTAssertEqual(matchChapters(input: "prologue", titles: []), [])
        XCTAssertEqual(matchChapters(input: "1", titles: []), [])
    }
}
