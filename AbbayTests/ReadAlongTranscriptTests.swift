//
//  ReadAlongTranscriptTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class ReadAlongTranscriptTests: XCTestCase {
    /// A line of `words`, one word per second, each lasting 0.8 s.
    private func line(_ start: Double, _ words: [String]) -> ReadAlongLine {
        let parts = words.enumerated().map { index, word in
            ReadAlongWord(text: word, start: start + Double(index), end: start + Double(index) + 0.8)
        }
        return ReadAlongLine(start: start, end: start + Double(words.count), words: parts)
    }

    private var sample: ReadAlongTranscript {
        var transcript = ReadAlongTranscript(language: "en-US")
        let lines = [line(10, ["Mr.", "and", "Mrs."]), line(20, ["Dursley"])]
        transcript.add(lines, covering: .init(start: 0, end: 30))
        return transcript
    }

    func test_position_insideAWord_returnsLineAndWord() {
        XCTAssertEqual(sample.position(at: 11.2), ReadAlongPosition(line: 0, word: 1))
    }

    func test_position_betweenWordsOfALine_keepsLine_noWord() {
        // 11.9 is after "and" ends (11.8) and before "Mrs." starts (12.0)
        XCTAssertEqual(sample.position(at: 11.9), ReadAlongPosition(line: 0, word: nil))
    }

    func test_position_inAGapBetweenLines_holdsThePreviousLine() {
        XCTAssertEqual(sample.position(at: 15), ReadAlongPosition(line: 0, word: nil))
    }

    func test_position_atALineStart_returnsItsFirstWord() {
        XCTAssertEqual(sample.position(at: 20), ReadAlongPosition(line: 1, word: 0))
    }

    func test_position_beforeFirstLine_isNil() {
        XCTAssertNil(sample.position(at: 5))
    }

    func test_position_emptyTranscript_isNil() {
        XCTAssertNil(ReadAlongTranscript(language: "en-US").position(at: 5))
    }

    func test_add_overlappingRuns_mergesCoveredAndDropsDuplicateLines() {
        var transcript = ReadAlongTranscript(language: "en-US")
        transcript.add([line(10, ["a"])], covering: .init(start: 0, end: 15))
        transcript.add([line(10, ["a"]), line(20, ["b"])], covering: .init(start: 8, end: 25))
        XCTAssertEqual(transcript.lines.map(\.start), [10, 20])
        XCTAssertEqual(transcript.covered, [ReadAlongSpan(start: 0, end: 25)])
    }

    func test_add_replacesALineWithinFiftyMillisecondsOfAnIncomingOne() {
        var transcript = ReadAlongTranscript(language: "en-US")
        transcript.add([line(10, ["old"])], covering: .init(start: 0, end: 15))
        transcript.add([line(10.04, ["new"])], covering: .init(start: 5, end: 20))
        XCTAssertEqual(transcript.lines.map(\.text), ["new"])
    }

    func test_add_keepsALineMoreThanFiftyMillisecondsAway() {
        var transcript = ReadAlongTranscript(language: "en-US")
        transcript.add([line(10, ["old"])], covering: .init(start: 0, end: 15))
        transcript.add([line(10.06, ["new"])], covering: .init(start: 5, end: 20))
        XCTAssertEqual(transcript.lines.map(\.text), ["old", "new"])
    }

    func test_add_outOfOrderRuns_keepsLinesSorted() {
        var transcript = ReadAlongTranscript(language: "en-US")
        transcript.add([line(100, ["late"]), line(110, ["later"])], covering: .init(start: 95, end: 120))
        transcript.add([line(0, ["early"]), line(10, ["next"])], covering: .init(start: 0, end: 20))
        XCTAssertEqual(transcript.lines.map(\.start), [0, 10, 100, 110])
        XCTAssertEqual(transcript.covered, [ReadAlongSpan(start: 0, end: 20), ReadAlongSpan(start: 95, end: 120)])
    }

    func test_add_touchingSpans_merge() {
        var transcript = ReadAlongTranscript(language: "en-US")
        transcript.add([], covering: .init(start: 0, end: 10))
        transcript.add([], covering: .init(start: 10, end: 20))
        XCTAssertEqual(transcript.covered, [ReadAlongSpan(start: 0, end: 20)])
    }

    func test_isCovered() {
        var transcript = ReadAlongTranscript(language: "en-US")
        transcript.add([], covering: .init(start: 0, end: 25))
        transcript.add([], covering: .init(start: 60, end: 70))
        XCTAssertTrue(transcript.isCovered(24))
        XCTAssertFalse(transcript.isCovered(30))
        XCTAssertTrue(transcript.isCovered(65))
        XCTAssertFalse(transcript.isCovered(70))
    }

    func test_line_text_joinsWordsWithASpace() {
        XCTAssertEqual(line(10, ["Mr.", "and", "Mrs."]).text, "Mr. and Mrs.")
    }

    func test_codableRoundTrip() throws {
        let original = sample
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReadAlongTranscript.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_codable_doesNotEncodeTheDerivedLineText() throws {
        let data = try JSONEncoder().encode(line(10, ["a"]))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["text"])
    }
}
