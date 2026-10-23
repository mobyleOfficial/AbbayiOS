//
//  ArchiveSearchQueryTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class ArchiveSearchQueryTests: XCTestCase {
    private let catalog = "collection:librivoxaudio AND mediatype:audio"

    func test_search_eachTermInTitleOrCreator_joinedWithAND_lastTermAsPrefix() {
        XCTAssertEqual(
            ArchiveSearchQuery.search("The Time Machine"),
            "\(catalog) AND (title:the OR creator:the) AND (title:time OR creator:time)"
                + " AND (title:machine* OR creator:machine*)"
        )
    }

    /// A title word and an author word together: neither field holds both.
    func test_search_mixesTitleAndCreatorTerms() {
        XCTAssertEqual(
            ArchiveSearchQuery.search("Alice Carroll"),
            "\(catalog) AND (title:alice OR creator:alice) AND (title:carroll* OR creator:carroll*)"
        )
    }

    func test_search_singleTerm() {
        XCTAssertEqual(
            ArchiveSearchQuery.search("wonderland"),
            "\(catalog) AND (title:wonderland* OR creator:wonderland*)"
        )
    }

    func test_search_blank_isNil() {
        XCTAssertNil(ArchiveSearchQuery.search(""))
        XCTAssertNil(ArchiveSearchQuery.search("   \n "))
    }

    func test_search_collapsesWhitespace() {
        XCTAssertEqual(ArchiveSearchQuery.terms(in: "  dom \t  casmurro "), ["dom", "casmurro"])
    }

    func test_terms_escapeLuceneSpecialCharacters() {
        XCTAssertEqual(
            ArchiveSearchQuery.terms(in: #"a:b (c) "d" e* f? g~ h^ i\ j/ k-l m!n [o] {p} q&&r s||t"#),
            [
                #"a\:b"#, #"\(c\)"#, #"\"d\""#, #"e\*"#, #"f\?"#, #"g\~"#, #"h\^"#, #"i\\"#, #"j\/"#,
                #"k\-l"#, #"m\!n"#, #"\[o\]"#, #"\{p\}"#, #"q\&\&r"#, #"s\|\|t"#
            ]
        )
    }

    func test_search_userWildcardIsEscaped_onlyOurPrefixWildcardIsLive() {
        XCTAssertEqual(
            ArchiveSearchQuery.search("al*"),
            #"\#(catalog) AND (title:al\** OR creator:al\**)"#
        )
    }

    func test_terms_plusIsASeparator() {
        XCTAssertEqual(ArchiveSearchQuery.terms(in: "pride+prejudice"), ["pride", "prejudice"])
    }

    func test_terms_lowercaseSoOperatorsAreWords() {
        XCTAssertEqual(ArchiveSearchQuery.terms(in: "War AND Peace OR NOT"), ["war", "and", "peace", "or", "not"])
    }

    func test_terms_keepNonASCII() {
        XCTAssertEqual(ArchiveSearchQuery.terms(in: "Memórias Póstumas"), ["memórias", "póstumas"])
        XCTAssertEqual(ArchiveSearchQuery.terms(in: "Война и мир"), ["война", "и", "мир"])
        XCTAssertEqual(
            ArchiveSearchQuery.search("Dom Casmurro"),
            "\(catalog) AND (title:dom OR creator:dom) AND (title:casmurro* OR creator:casmurro*)"
        )
    }

    func test_normalized_sameForEquivalentQueries() {
        XCTAssertEqual(ArchiveSearchQuery.normalized("  Alice  in Wonderland"), "alice in wonderland")
        XCTAssertNotEqual(ArchiveSearchQuery.normalized("alice"), ArchiveSearchQuery.normalized("alice in"))
    }

    func test_popular_isTheAudioCatalog() {
        XCTAssertEqual(ArchiveSearchQuery.popular, catalog)
    }
}
