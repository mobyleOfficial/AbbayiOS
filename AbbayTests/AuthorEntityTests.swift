//
//  AuthorEntityTests.swift
//  AbbayTests
//

@testable import Abbay
import AppIntents
import XCTest

/// #213: "Play <author> in Abbay". The authors are the library's artists, and the intent plays
/// #207's pick: the author's last-played book, else their first in library order.
final class AuthorEntityTests: XCTestCase {
    private var player = MockPlayer()
    private var loader = MockLoadAudioUseCase()
    private var lister = MockLoadAllAudiosUseCase()
    private var lastPlayed = LastPlayedStore(store: InMemoryKeyValueStore(), legacyStore: InMemoryKeyValueStore())

    override func setUpWithError() throws {
        try super.setUpWithError()
        player = MockPlayer()
        loader = MockLoadAudioUseCase()
        lister = MockLoadAllAudiosUseCase()
        let container = MockDependencyContainer(player: player, loadAudio: loader, loadAllAudios: lister)
        lastPlayed = container.lastPlayed
        DependencyContainer.configure(with: container)
    }

    override func tearDownWithError() throws {
        DependencyContainer.reset()
        try super.tearDownWithError()
    }

    private func book(_ title: String, by artist: String, _ url: String) -> AudioModel {
        var model = AudioModel()
        model.title = title
        model.artist = artist
        model.url = URL(string: url)
        loader.stubs[url] = model
        return model
    }

    private lazy var library = [
        book("Emma", by: "Jane Austen", "file:///emma"),
        book("Dom Casmurro", by: "Machado de Assis", "file:///dom"),
        book("Persuasion", by: "Jane Austen", "file:///persuasion"),
        book("Untitled Notes", by: "", "file:///notes"),
        book("O Alienista", by: "machado de assis", "file:///alienista")
    ]

    // MARK: - The authors

    func test_authors_areTheDistinctArtists_inLibraryOrder() {
        XCTAssertEqual(LibraryAuthors.all(in: library, lastPlayedURL: nil), ["Jane Austen", "Machado de Assis"])
    }

    func test_authors_lastPlayedBooksAuthorFirst() throws {
        let url = try XCTUnwrap(URL(string: "file:///alienista"))
        XCTAssertEqual(LibraryAuthors.all(in: library, lastPlayedURL: url), ["machado de assis", "Jane Austen"])
    }

    func test_suggested_areCappedForThePhraseBudget() async throws {
        lister.stub = (0..<(AuthorEntityQuery.suggestionLimit + 5)).map { book("Book \($0)", by: "Author \($0)", "file:///b\($0)") }
        let suggested = try await AuthorEntityQuery().suggestedEntities()
        XCTAssertEqual(suggested.count, AuthorEntityQuery.suggestionLimit)
        XCTAssertEqual(suggested.first?.name, "Author 0")
    }

    /// The App Shortcut parameters are re-read from the library on every publish.
    func test_suggested_followTheLibrary() async throws {
        lister.stub = library
        let before = try await AuthorEntityQuery().suggestedEntities()
        XCTAssertEqual(before.map(\.name), ["Jane Austen", "Machado de Assis"])
        lister.stub = [book("Dracula", by: "Bram Stoker", "file:///dracula")]
        let after = try await AuthorEntityQuery().suggestedEntities()
        XCTAssertEqual(after.map(\.name), ["Bram Stoker"])
    }

    func test_entitiesForIdentifiers_dropsAuthorsNoLongerInTheLibrary() async throws {
        lister.stub = library
        let found = try await AuthorEntityQuery().entities(for: ["Jane Austen", "Bram Stoker"])
        XCTAssertEqual(found.map(\.id), ["Jane Austen"])
    }

    func test_matching_readsWhatWasSaidAsAnAuthor() async throws {
        lister.stub = library
        let query = AuthorEntityQuery()
        let cases: [(String, [String])] = [
            ("jane austen", ["Jane Austen"]),
            ("Austen", ["Jane Austen"]),
            ("something by jane austen", ["Jane Austen"]),
            ("machado de assis", ["Machado de Assis"]),
            ("um livro do machado", ["Machado de Assis"]),
            ("bram stoker", []),
            ("de", [])
        ]
        for (spoken, names) in cases {
            let found = try await query.entities(matching: spoken)
            XCTAssertEqual(found.map(\.name), names, spoken)
        }
    }

    func test_entity_showsTheAuthorsName() {
        XCTAssertEqual(AuthorEntity(name: "Jane Austen").displayRepresentation.title.resolved(in: "en"), "Jane Austen")
    }

    // MARK: - What it plays

    func test_book_isTheFirstInLibraryOrder_whenNoneWasPlayed() {
        XCTAssertEqual(LibraryAuthors.book(by: "Jane Austen", in: library, lastPlayedURL: nil)?.title, "Emma")
    }

    func test_book_isTheAuthorsLastPlayed() throws {
        let url = try XCTUnwrap(URL(string: "file:///persuasion"))
        XCTAssertEqual(LibraryAuthors.book(by: "Jane Austen", in: library, lastPlayedURL: url)?.title, "Persuasion")
        // Someone else's last-played book changes nothing.
        let other = try XCTUnwrap(URL(string: "file:///dom"))
        XCTAssertEqual(LibraryAuthors.book(by: "Jane Austen", in: library, lastPlayedURL: other)?.title, "Emma")
    }

    /// Spellings that differ in case are one author, and both books are theirs.
    func test_book_matchesTheAuthorIgnoringCaseAndAccents() throws {
        let library = library
        let machado = { (lastPlayed: URL?) in
            LibraryAuthors.book(by: "Machado de Assis", in: library, lastPlayedURL: lastPlayed)?.title
        }
        let url = try XCTUnwrap(URL(string: "file:///alienista"))
        XCTAssertEqual(machado(url), "O Alienista")
        XCTAssertEqual(machado(nil), "Dom Casmurro")
    }

    func test_book_none_forAnAuthorNoLongerInTheLibrary() {
        XCTAssertNil(LibraryAuthors.book(by: "Bram Stoker", in: library, lastPlayedURL: nil))
    }

    // MARK: - PlayAuthorIntent

    func test_intent_playsTheAuthorsLastPlayedBook() async throws {
        lister.stub = library
        lastPlayed.save(url: try XCTUnwrap(URL(string: "file:///persuasion")))
        var intent = PlayAuthorIntent()
        intent.author = AuthorEntity(name: "Jane Austen")
        _ = try await intent.perform()
        XCTAssertEqual(player.playCalls.map(\.title), ["Persuasion"])
    }

    func test_intent_unknownAuthor_doesNotPlay() async throws {
        lister.stub = library
        var intent = PlayAuthorIntent()
        intent.author = AuthorEntity(name: "Bram Stoker")
        _ = try await intent.perform()
        XCTAssertTrue(player.playCalls.isEmpty)
    }

    func test_intent_noBookDialog_inBothLanguages() {
        let noBook = PlayAuthorIntent.noBookDialog("Bram Stoker")
        XCTAssertEqual(noBook.resolved(in: "en"), "No audiobook by Bram Stoker in Abbay.")
        XCTAssertEqual(noBook.resolved(in: "pt-BR"), "Nenhum audiolivro de Bram Stoker no Abbay.")
    }
}
