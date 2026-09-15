//
//  FuzzyMatchTests.swift
//  AbbayIntentsTests
//

import XCTest

// NOTE: AbbayIntents source files are compiled directly into this test bundle
// (see project.yml). We do NOT `@testable import AbbayIntents` because an
// app-extension binary cannot be linked into a test bundle; the same source
// files compile into both modules with identical visibility.

final class ExtensionFuzzyMatchTests: XCTestCase {
    func test_matchAll_singleExactMatch_returnsOne() {
        var audio = AudioModel(url: URL(string: "file:///a"))
        audio.title = "Harry Potter"
        let results = matchAll(input: "Harry Potter", audios: [audio], lastPlayedURL: nil)
        XCTAssertEqual(results.count, 1)
    }

    func test_matchAll_topScoreOnly_returnsAllAtTop() {
        var audioA = AudioModel(url: URL(string: "file:///a"))
        audioA.title = "Harry Potter and the Sorcerer's Stone"
        var audioB = AudioModel(url: URL(string: "file:///b"))
        audioB.title = "Harry Potter and the Chamber of Secrets"
        var audioC = AudioModel(url: URL(string: "file:///c"))
        audioC.title = "Star Wars"

        let results = matchAll(input: "Harry Potter", audios: [audioA, audioB, audioC], lastPlayedURL: nil)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains(where: { $0.title.contains("Sorcerer") }))
        XCTAssertTrue(results.contains(where: { $0.title.contains("Chamber") }))
    }

    func test_matchAll_lastPlayedTiebreak() {
        var audioA = AudioModel(url: URL(string: "file:///a"))
        audioA.title = "Harry Potter and the Sorcerer's Stone"
        var audioB = AudioModel(url: URL(string: "file:///b"))
        audioB.title = "Harry Potter and the Chamber of Secrets"

        let results = matchAll(input: "Harry Potter", audios: [audioA, audioB], lastPlayedURL: audioB.url)
        XCTAssertEqual(results.first?.url, audioB.url)
    }

    func test_matchAll_emptyInput_returnsEmpty() {
        var audio = AudioModel(url: URL(string: "file:///a"))
        audio.title = "Anything"
        XCTAssertEqual(matchAll(input: "", audios: [audio], lastPlayedURL: nil).count, 0)
    }

    func test_matchAll_ampersandNormalization() {
        var audio = AudioModel(url: URL(string: "file:///a"))
        audio.title = "Harry Potter and the Philosophers Stone"
        let results = matchAll(input: "Harry Potter & the Philosophers Stone", audios: [audio], lastPlayedURL: nil)
        XCTAssertEqual(results.count, 1)
    }

    func test_matchAll_topScoreFilter_doesNotReturnLowerScores() {
        var audioA = AudioModel(url: URL(string: "file:///a"))
        audioA.title = "Harry Potter"  // exact match → score 3
        var audioB = AudioModel(url: URL(string: "file:///b"))
        audioB.title = "Harry Potter and the Goblet of Fire"  // prefix → score 2

        let results = matchAll(input: "Harry Potter", audios: [audioA, audioB], lastPlayedURL: nil)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.url, audioA.url)
    }
}
