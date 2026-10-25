//
//  SpokenAuthorMatchingTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Author-only requests (#207): "play something by Jane Austen", "toca um livro do Machado de
/// Assis". `matchAll` serves every Siri path (SiriKit, the App Shortcuts entity query, the iOS 27
/// audio domain); `MediaSearchResolver` adds SiriKit's separate `artistName`.
final class SpokenAuthorMatchingTests: XCTestCase {
    private struct Case {
        let query: String
        let expected: [String]
        let lastPlayed: String?
        let line: UInt

        init(_ query: String, _ expected: [String], lastPlayed: String? = nil, line: UInt = #line) {
            self.query = query
            self.expected = expected
            self.lastPlayed = lastPlayed
            self.line = line
        }
    }

    private func book(_ title: String, _ artist: String) -> AudioModel {
        var model = AudioModel()
        model.title = title
        model.artist = artist
        let slug = "\(title)-\(artist)".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? title
        model.url = URL(string: "file:///\(slug)")
        return model
    }

    private lazy var english: [AudioModel] = [
        book("Pride and Prejudice", "Jane Austen"),
        book("Harry Potter and the Goblet of Fire", "J. K. Rowling"),
        book("Emma", "Jane Austen"),
        book("Persuasion", "Jane Austen"),
        book("Dracula", "Bram Stoker"),
        book("The Jungle Book", "Rudyard Kipling"),
        book("Book One", "Stephen King"),
        book("It", "Stephen King")
    ]

    private lazy var portuguese: [AudioModel] = [
        book("Dom Casmurro", "Machado de Assis"),
        book("Iracema", "José de Alencar"),
        book("O Alienista", "Machado de Assis"),
        book("Livro do Desassossego", "Fernando Pessoa"),
        book("A Moreninha", "Joaquim Manuel de Macedo")
    ]

    private func check(_ cases: [Case], in library: [AudioModel]) {
        for testCase in cases {
            let lastPlayed = testCase.lastPlayed.flatMap { title in library.first { $0.title == title }?.url }
            let found = matchAll(input: testCase.query, audios: library, lastPlayedURL: lastPlayed)
            XCTAssertEqual(found.map(\.title), testCase.expected, "\"\(testCase.query)\"", line: testCase.line)
        }
    }

    func test_english_authorOnly_offersTheirBooks_inLibraryOrder() {
        let austen = ["Pride and Prejudice", "Emma", "Persuasion"]
        let cases: [Case] = [
            Case("something by Jane Austen", austen),
            Case("anything by jane austen", austen),
            Case("a book by Jane Austen", austen),
            Case("an audiobook by austen", austen),
            Case("books by Jane Austen", austen),
            Case("by Jane Austen", austen),
            Case("something from jane austen", austen),
            Case("Jane Austen", austen),
            Case("austen", austen),
            Case("something by Bram Stoker", ["Dracula"]),
            Case("something by J. K. Rowling", ["Harry Potter and the Goblet of Fire"]),
            Case("something by rowling", ["Harry Potter and the Goblet of Fire"]),
            Case("something by Stephen King", ["Book One", "It"])
        ]
        check(cases, in: english)
    }

    func test_english_authorOnly_prefersTheLastPlayedOfTheirBooks() {
        let cases: [Case] = [
            Case("something by Jane Austen", ["Emma"], lastPlayed: "Emma"),
            Case("jane austen", ["Persuasion"], lastPlayed: "Persuasion"),
            // The last-played book is someone else's: theirs, in library order.
            Case("something by Jane Austen", ["Pride and Prejudice", "Emma", "Persuasion"], lastPlayed: "Dracula")
        ]
        check(cases, in: english)
    }

    /// Titles still win, and a request word in a title doesn't hand the author's request away.
    func test_english_titlesStillWin() {
        let cases: [Case] = [
            Case("emma by jane austen", ["Emma"]),
            Case("emma", ["Emma"]),
            Case("pride and prejudice by austen", ["Pride and Prejudice"]),
            Case("the jungle book", ["The Jungle Book"]),
            Case("a book by Rudyard Kipling", ["The Jungle Book"]),
            // "a book" is not *The Jungle Book* when Kipling isn't the one asked for.
            Case("a book by Bram Stoker", ["Dracula"]),
            // A title said with its author.
            Case("book one by stephen king", ["Book One"]),
            Case("dracula by bram stoker", ["Dracula"])
        ]
        check(cases, in: english)
    }

    func test_english_negatives() {
        let cases: [Case] = [
            Case("something by Agatha Christie", []),
            Case("something by Stephen Hawking", []),
            Case("something by", []),
            Case("by", []),
            Case("something", []),
            Case("by j", []),
            Case("something by the", []),
            Case("jane", ["Pride and Prejudice", "Emma", "Persuasion"]),
            Case("something by someone else", []),
            Case("harry potter and the half blood prince", []),
            Case("star wars", [])
        ]
        check(cases, in: english)
    }

    func test_portuguese_authorOnly_offersTheirBooks() {
        let machado = ["Dom Casmurro", "O Alienista"]
        let cases: [Case] = [
            Case("um livro do Machado de Assis", machado),
            Case("um livro de Machado de Assis", machado),
            Case("algo de machado de assis", machado),
            Case("alguma coisa do Machado de Assis", machado),
            Case("livros do machado", machado),
            Case("um audiolivro de machado de assis", machado),
            Case("toca um livro do Machado de Assis", machado),
            Case("Machado de Assis", machado),
            Case("machado", machado),
            Case("um livro de José de Alencar", ["Iracema"]),
            Case("algo do jose de alencar", ["Iracema"]),
            Case("um livro do Machado de Assis", ["O Alienista"], lastPlayed: "O Alienista")
        ]
        check(cases, in: portuguese)
    }

    func test_portuguese_titlesStillWin() {
        let cases: [Case] = [
            Case("dom casmurro de machado de assis", ["Dom Casmurro"]),
            Case("o alienista por machado de assis", ["O Alienista"]),
            Case("a moreninha de joaquim manuel de macedo", ["A Moreninha"]),
            // "livro do …" is a request shape, but Desassossego is no author: the title.
            Case("livro do desassossego", ["Livro do Desassossego"]),
            Case("o livro do desassossego", ["Livro do Desassossego"])
        ]
        check(cases, in: portuguese)
    }

    func test_portuguese_negatives() {
        // Without *Livro do Desassossego*, whose title holds "livro" (which on its own is a title word).
        let library = portuguese.filter { !$0.title.hasPrefix("Livro") }
        let cases: [Case] = [
            Case("um livro do Jorge Amado", []),
            Case("algo de Clarice Lispector", []),
            Case("um livro de", []),
            Case("um livro", []),
            Case("algo", []),
            Case("de", []),
            Case("do", []),
            Case("o cortiço", []),
            Case("um livro de machado de alencar", [])
        ]
        check(cases, in: library)
    }

    // MARK: - SiriKit's separate artist

    private func resolve(_ title: String, _ artist: String?, lastPlayed: URL? = nil) -> [String] {
        MediaSearchResolver.candidates(
            mediaName: title,
            artistName: artist,
            audios: english,
            lastPlayedURL: lastPlayed
        ).map(\.title)
    }

    func test_resolver_artistAlone_asksForTheirBooks() {
        XCTAssertEqual(resolve("", "Jane Austen"), ["Pride and Prejudice", "Emma", "Persuasion"])
    }

    func test_resolver_artistAlone_prefersTheirLastPlayed() {
        XCTAssertEqual(resolve(" ", "jane austen", lastPlayed: english[2].url), ["Emma"])
    }

    func test_resolver_artistAlone_unknown_matchesNothing_ratherThanResuming() {
        XCTAssertEqual(resolve("", "Agatha Christie", lastPlayed: english[4].url), [])
    }

    func test_resolver_titleAndArtist_readAsTitleByAuthor() {
        let library = [book("Dracula", "Various"), book("Dracula", "Bram Stoker")]
        let found = MediaSearchResolver.candidates(
            mediaName: "Dracula",
            artistName: "Bram Stoker",
            audios: library,
            lastPlayedURL: nil
        )
        XCTAssertEqual(found.map(\.artist), ["Bram Stoker"])
    }

    func test_resolver_noTitleNoArtist_stillResumes() {
        XCTAssertEqual(resolve("", "  ", lastPlayed: english[4].url), ["Dracula"])
    }

    func test_matchAuthor_takesTheRequestShapeOrABareName() {
        let library = english
        let author = { (input: String) in matchAuthor(input: input, audios: library, lastPlayedURL: nil).map(\.title) }
        XCTAssertEqual(author("something by Bram Stoker"), ["Dracula"])
        XCTAssertEqual(author("Bram Stoker"), ["Dracula"])
        XCTAssertEqual(author("Dracula"), [])
    }
}
