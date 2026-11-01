//
//  ChapterHeadingDetectorTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Chapters found in a transcript by the headings its narrator reads out: a heading keyword after a
/// pause, with a number where the keyword takes one.
final class ChapterHeadingDetectorTests: XCTestCase {
    // MARK: - Headings

    func test_heading_afterAPause_isFound_withItsNumberAsSaid() {
        let lines = transcript([
            (0, "It was a dark and stormy night"),
            (100, "Chapter Two. The storm"),
            (200, "Chapter 3 And then")
        ])

        let headings = ChapterHeadingDetector.headings(in: lines)

        XCTAssertEqual(headings.map(\.title), ["Chapter Two", "Chapter 3"])
        XCTAssertEqual(headings.map(\.start), [100, 200])
    }

    func test_mention_withoutAPause_isNotAHeading() {
        // "chapter two" mid-sentence: its words follow the one before at once.
        let words = spoken("as we saw in chapter two the hero", from: 50)
            + spoken("Chapter Three", from: 300)
        let headings = ChapterHeadingDetector.headings(in: [ReadAlongLine(start: 50, end: 310, words: words)])

        XCTAssertEqual(headings.map(\.title), ["Chapter Three"])
    }

    func test_numberedKeyword_withoutANumber_isNotAHeading() {
        let lines = transcript([(0, "Part of the problem was"), (100, "Book lovers will know"), (200, "Chapter One")])

        XCTAssertEqual(ChapterHeadingDetector.headings(in: lines).map(\.title), ["Chapter One"])
    }

    func test_numberWords_romanNumerals_andCompoundNumbers() {
        let lines = transcript([
            (0, "Part II"),
            (100, "Chapter twenty-one. A visit"),
            (200, "Chapter twenty one and more"),
            (300, "Book the first")
        ])

        XCTAssertEqual(
            ChapterHeadingDetector.headings(in: lines).map(\.title),
            ["Part II", "Chapter Twenty-One", "Chapter Twenty One"],
            "\"and more\" isn't a number: the connector is dropped; \"the\" isn't one either"
        )
    }

    func test_standaloneKeywords_needNoNumber() {
        let lines = transcript([(0, "Prologue."), (100, "Chapter 1"), (200, "Epilogue")])

        XCTAssertEqual(ChapterHeadingDetector.headings(in: lines).map(\.title), ["Prologue", "Chapter 1", "Epilogue"])
    }

    func test_portugueseAndSpanish_headings() {
        let lines = transcript([
            (0, "Capítulo um. A chegada"),
            (100, "Capítulo vinte e dois"),
            (200, "Prólogo"),
            (300, "Capítulo cuatro")
        ])

        XCTAssertEqual(
            ChapterHeadingDetector.headings(in: lines).map(\.title),
            ["Capítulo Um", "Capítulo Vinte e Dois", "Prólogo", "Capítulo Cuatro"]
        )
    }

    /// LibriVox reads "Chapter 1 of Emma. This is a LibriVox recording…" and then "Chapter 1." again.
    func test_headings_closerThanTheMinimumChapter_areOne_theFirstWins() {
        let lines = transcript([(2, "Chapter 1 of Emma"), (20, "Chapter 1"), (400, "Chapter 2")])

        let headings = ChapterHeadingDetector.headings(in: lines)

        XCTAssertEqual(headings.map(\.title), ["Chapter 1", "Chapter 2"])
        XCTAssertEqual(headings.map(\.start), [2, 400])
    }

    /// From a real narration: the text starts after the heading's pause, and its first word can be
    /// a number ("Chapter 2. … One time, when I…", "Chapter 11. … 60 seconds").
    func test_number_endsAtThePause_andNothingFollowsDigits() {
        let words = spoken("Chapter 2.", from: 100) + spoken("One time when I was", from: 103)
            + spoken("Chapter 15 I enter a nightmare", from: 300)
            + spoken("Chapter twenty", from: 500) + spoken("one more time", from: 503)

        let headings = ChapterHeadingDetector.headings(in: [ReadAlongLine(start: 100, end: 510, words: words)])

        XCTAssertEqual(headings.map(\.title), ["Chapter 2", "Chapter 15", "Chapter Twenty"])
    }

    /// From a real narration: "Part one. The Tribute. Chapter one." A part's first chapter keeps its
    /// name; a repeated chapter heading still doesn't.
    func test_aPartsFirstChapter_joinsThePartHeading() {
        let lines = transcript([
            (52, "Part one."), (53.5, "The Tribute."), (56, "Chapter one. When I wake up"),
            (2034, "Chapter 2."),
            (13_377, "Part two. The games."), (13_380, "Chapter 10.")
        ])

        let headings = ChapterHeadingDetector.headings(in: lines)

        XCTAssertEqual(headings.map(\.title), ["Part One · Chapter One", "Chapter 2", "Part Two · Chapter 10"])
        XCTAssertEqual(headings.map(\.start), [52, 2034, 13_377])
    }

    // MARK: - Chapters

    func test_chapters_coverTheBook_eachUntilTheNext() {
        let lines = transcript([(5, "Chapter One"), (100, "Chapter Two"), (250, "Chapter Three")])

        let chapters = ChapterHeadingDetector.chapters(in: lines, duration: 400, openingTitle: "Opening")

        XCTAssertEqual(chapters.map(\.title), ["Chapter One", "Chapter Two", "Chapter Three"])
        XCTAssertEqual(chapters.map(\.startTime), [0, 100, 250], "a short lead-in joins the first chapter")
        XCTAssertEqual(chapters.map(\.duration), [100, 150, 150])
    }

    func test_chapters_aLongOpening_isAChapterOfItsOwn() {
        let lines = transcript([(0, "Music and credits"), (90, "Chapter One"), (300, "Chapter Two")])

        let chapters = ChapterHeadingDetector.chapters(in: lines, duration: 600, openingTitle: "Opening")

        XCTAssertEqual(chapters.map(\.title), ["Opening", "Chapter One", "Chapter Two"])
        XCTAssertEqual(chapters.map(\.startTime), [0, 90, 300])
        XCTAssertEqual(chapters.map(\.duration), [90, 210, 300])
    }

    func test_chapters_fewerThanTwoHeadings_areNone() {
        let one = transcript([(0, "Introduction"), (100, "Then the story goes on")])

        XCTAssertTrue(ChapterHeadingDetector.chapters(in: one, duration: 500, openingTitle: "Opening").isEmpty)
        XCTAssertTrue(ChapterHeadingDetector.chapters(in: [], duration: 500, openingTitle: "Opening").isEmpty)
    }

    /// A search continued from the last chapter found (#316): its own heading is heard again at the
    /// start and isn't added twice; the chapters before stay; new ones are added after it.
    func test_extending_addsTheHeadingsAfterTheLastChapter() {
        let found = [
            ChapterModel(title: "Opening", startTime: 0, duration: 90),
            ChapterModel(title: "Chapter One", startTime: 90, duration: 510)
        ]
        let lines = transcript([(90, "Chapter One"), (300, "Chapter Two"), (450, "Chapter Three")])

        let chapters = ChapterHeadingDetector.extending(found, with: lines, duration: 600)

        XCTAssertEqual(chapters.map(\.title), ["Opening", "Chapter One", "Chapter Two", "Chapter Three"])
        XCTAssertEqual(chapters.map(\.startTime), [0, 90, 300, 450])
        XCTAssertEqual(chapters.map(\.duration), [90, 210, 150, 150])
        XCTAssertEqual(
            ChapterHeadingDetector.extending(found, with: transcript([(90, "Chapter One")]), duration: 600),
            found,
            "nothing new heard: unchanged"
        )
    }

    func test_stubHeadingLines_giveThreeChapters() {
        let lines = StubReadAlongTranscriber.chapterHeadingLines(from: 0, to: 200)

        let chapters = ChapterHeadingDetector.chapters(in: lines, duration: 200, openingTitle: "Opening")

        XCTAssertEqual(chapters.map(\.title), ["Chapter One", "Chapter Two", "Chapter Three"])
        XCTAssertEqual(chapters.map(\.startTime), [0, 70, 130])
    }

    // MARK: - Helpers

    /// Each phrase a line of its own, words 0.4 s apart, so a phrase's start follows a pause.
    private func transcript(_ phrases: [(start: Double, text: String)]) -> [ReadAlongLine] {
        phrases.map { phrase in
            let words = spoken(phrase.text, from: phrase.start)
            return ReadAlongLine(start: phrase.start, end: words.last?.end ?? phrase.start, words: words)
        }
    }

    private func spoken(_ text: String, from start: Double) -> [ReadAlongWord] {
        text.split(separator: " ").enumerated().map { index, word in
            let wordStart = start + Double(index) * 0.4
            return ReadAlongWord(text: String(word), start: wordStart, end: wordStart + 0.3)
        }
    }
}
