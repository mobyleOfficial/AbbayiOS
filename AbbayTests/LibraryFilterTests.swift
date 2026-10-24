//
//  LibraryFilterTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The Library's local search: title or author, ignoring case and diacritics, never the network.
final class LibraryFilterTests: XCTestCase {
    private let pride = AudioModel(title: "Pride and Prejudice", artist: "Jane Austen", url: URL(string: "file:///f/pride.m4b"))
    private let orgulho = AudioModel(title: "Orgulho e Preconceito", artist: "Jane Austen", url: URL(string: "file:///f/orgulho.m4b"))
    private let memorias = AudioModel(
        title: "Memórias Póstumas de Brás Cubas",
        artist: "Machado de Assis",
        url: URL(string: "file:///f/memorias.m4b")
    )

    private var library: [AudioModel] { [pride, orgulho, memorias] }

    private func titles(_ query: String) -> [String] {
        LibraryFilter.filter(library, query: query).map(\.title)
    }

    func test_matchesTitle() {
        XCTAssertEqual(titles("Prejudice"), ["Pride and Prejudice"])
    }

    func test_matchesArtist() {
        XCTAssertEqual(titles("Machado"), ["Memórias Póstumas de Brás Cubas"])
    }

    func test_ignoresCase() {
        XCTAssertEqual(titles("PRIDE"), ["Pride and Prejudice"])
        XCTAssertEqual(titles("orgulho"), ["Orgulho e Preconceito"])
    }

    func test_ignoresDiacritics() {
        XCTAssertEqual(titles("memorias"), ["Memórias Póstumas de Brás Cubas"])
    }

    func test_blankQuery_returnsAll() {
        XCTAssertEqual(titles(""), library.map(\.title))
        XCTAssertEqual(titles("   "), library.map(\.title))
    }

    func test_noMatch_returnsEmpty() {
        XCTAssertEqual(titles("zzzzqqq"), [])
    }
}
