//
//  SpokenQueryMatchingTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// `matchAll` against what people actually say to Siri, extra words included (#201). Every Siri
/// path matches through it: SiriKit `INPlayMediaIntent` (extension and in-app), the App Shortcuts
/// entity query and the iOS 27 audio domain.
final class SpokenQueryMatchingTests: XCTestCase {
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

    private func book(_ title: String, _ artist: String = "") -> AudioModel {
        var model = AudioModel()
        model.title = title
        model.artist = artist
        let slug = "\(title)-\(artist)".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? title
        model.url = URL(string: "file:///\(slug)")
        return model
    }

    private lazy var english: [AudioModel] = [
        book("Harry Potter and the Goblet of Fire", "J. K. Rowling"),
        book("Harry Potter and the Chamber of Secrets", "J. K. Rowling"),
        book("The Lord of the Rings", "J. R. R. Tolkien"),
        book("Pride and Prejudice", "Jane Austen"),
        book("Emma", "Jane Austen"),
        book("Stand by Me", "Stephen King"),
        book("Dracula", "Bram Stoker"),
        book("Dracula", "Various"),
        book("Anne of Green Gables", "L. M. Montgomery")
    ]

    private lazy var portuguese: [AudioModel] = [
        book("Dom Casmurro", "Machado de Assis"),
        book("Memórias Póstumas de Brás Cubas", "Machado de Assis"),
        book("O Alienista", "Machado de Assis"),
        book("A Moreninha", "Joaquim Manuel de Macedo"),
        book("Iracema", "José de Alencar")
    ]

    private func check(_ cases: [Case], in library: [AudioModel]) {
        for testCase in cases {
            let lastPlayed = testCase.lastPlayed.flatMap { title in library.first { $0.title == title }?.url }
            let found = matchAll(input: testCase.query, audios: library, lastPlayedURL: lastPlayed)
            let described = found.map { "\($0.title) (\($0.artist))" }
            let expected = testCase.expected
            XCTAssertEqual(
                found.map(\.title),
                expected.map { $0.components(separatedBy: " (").first ?? $0 },
                "\"\(testCase.query)\" found \(described)",
                line: testCase.line
            )
            for (want, got) in zip(expected, described) where want.contains(" (") {
                XCTAssertEqual(got, want, "\"\(testCase.query)\"", line: testCase.line)
            }
        }
    }

    func test_english_spokenQueriesWithExtraWords() {
        let cases: [Case] = [
            Case("the goblet of fire", ["Harry Potter and the Goblet of Fire"]),
            Case("goblet of fire", ["Harry Potter and the Goblet of Fire"]),
            Case("Harry Potter and the Goblet of Fire", ["Harry Potter and the Goblet of Fire"]),
            Case("harry potter goblet of fire", ["Harry Potter and the Goblet of Fire"]),
            Case("goblet of fire by rowling", ["Harry Potter and the Goblet of Fire"]),
            Case("Harry Potter and the Goblet of Fire by J.K. Rowling", ["Harry Potter and the Goblet of Fire"]),
            Case("harry potter and the goblet of fire by j k rowling", ["Harry Potter and the Goblet of Fire"]),
            Case("the goblet of fire audiobook", ["Harry Potter and the Goblet of Fire"]),
            Case("the audiobook harry potter and the chamber of secrets", ["Harry Potter and the Chamber of Secrets"]),
            Case("chamber of secrets", ["Harry Potter and the Chamber of Secrets"]),
            Case("lord of the rings", ["The Lord of the Rings"]),
            Case("the lord of the rings by tolkien", ["The Lord of the Rings"]),
            Case("PRIDE & PREJUDICE", ["Pride and Prejudice"]),
            Case("pride and prejudice by jane austen", ["Pride and Prejudice"]),
            Case("emma by jane austen", ["Emma"]),
            Case("Emma audiobook", ["Emma"]),
            Case("stand by me", ["Stand by Me"]),
            Case("stand by me by stephen king", ["Stand by Me"]),
            Case("anne of green gables", ["Anne of Green Gables"])
        ]
        check(cases, in: english)
    }

    func test_english_disambiguationAndLastPlayedBias_survive() {
        let goblet = "Harry Potter and the Goblet of Fire"
        let chamber = "Harry Potter and the Chamber of Secrets"
        let cases: [Case] = [
            // Two books share the words: both are offered, library order…
            Case("harry potter", [goblet, chamber]),
            // …or the last-played one first.
            Case("harry potter", [chamber, goblet], lastPlayed: chamber),
            // Same title twice: the author picks one.
            Case("dracula by bram stoker", ["Dracula (Bram Stoker)"]),
            Case("dracula", ["Dracula (Bram Stoker)", "Dracula (Various)"]),
            // An author that isn't the artist doesn't hide the title.
            Case("emma by someone else", ["Emma"])
        ]
        check(cases, in: english)
    }

    func test_english_negatives_doNotMatchOnCommonOrPartialWords() {
        let cases: [Case] = [
            Case("the", []),
            Case("a", []),
            Case("an", []),
            Case("of the", []),
            Case("and", []),
            Case("by", []),
            Case("go", []),
            Case("pot", []),
            Case("the lord of the flies", []),
            Case("harry potter and the half blood prince", []),
            Case("harry potter and the prisoner of azkaban", []),
            Case("audiobook", []),
            Case("star wars", [])
        ]
        check(cases, in: english)
    }

    func test_portuguese_spokenQueriesWithExtraWords() {
        let cases: [Case] = [
            Case("dom casmurro", ["Dom Casmurro"]),
            Case("o livro dom casmurro", ["Dom Casmurro"]),
            Case("dom casmurro por machado de assis", ["Dom Casmurro"]),
            Case("memorias postumas de bras cubas", ["Memórias Póstumas de Brás Cubas"]),
            Case("As Memórias Póstumas de Brás Cubas", ["Memórias Póstumas de Brás Cubas"]),
            Case("brás cubas", ["Memórias Póstumas de Brás Cubas"]),
            Case("o alienista", ["O Alienista"]),
            Case("alienista", ["O Alienista"]),
            Case("o alienista por machado de assis", ["O Alienista"]),
            Case("a moreninha de joaquim manuel de macedo", ["A Moreninha"]),
            Case("dom casmurro de machado de assis", ["Dom Casmurro"]),
            Case("o audiolivro iracema", ["Iracema"]),
            Case("iracema por josé de alencar", ["Iracema"])
        ]
        check(cases, in: portuguese)
    }

    func test_portuguese_negatives_doNotMatchOnCommonWords() {
        let cases: [Case] = [
            Case("o", []),
            Case("a", []),
            Case("de", []),
            Case("do", []),
            Case("da", []),
            Case("por", []),
            Case("o cortiço", []),
            Case("dom quixote", []),
            Case("livro", [])
        ]
        check(cases, in: portuguese)
    }

    func test_snapshot_carriesTheArtist_andOldSnapshotsStillDecode() throws {
        var model = book("Emma", "Jane Austen")
        model.url = URL(string: "file:///emma")
        let store = InMemoryKeyValueStore()
        LibrarySnapshotWriter(store: store, loadAllAudios: MockLoadAllAudiosUseCase(), publisher: NoOpPublisher())
            .write(audios: [model])
        let entry = try XCTUnwrap(LibrarySnapshotReader(store: store).read().first)
        XCTAssertEqual(entry.artist, "Jane Austen")
        XCTAssertEqual(MediaSearchResolver.audios(from: [entry]).first?.artist, "Jane Austen")

        let old = Data(#"{"version":1,"updatedAt":0,"audios":[{"title":"Emma","urlString":"file:///emma"}]}"#.utf8)
        let decoded = try JSONDecoder().decode(LibrarySnapshot.self, from: old)
        XCTAssertNil(decoded.audios.first?.artist)
        XCTAssertEqual(MediaSearchResolver.audios(from: decoded.audios).first?.artist, "")
    }
}

private struct NoOpPublisher: SiriLibraryPublisherProtocol {
    func publish(audios: [AudioModel], completion: @escaping () -> Void) {
        completion()
    }
}
