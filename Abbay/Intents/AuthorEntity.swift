//
//  AuthorEntity.swift
//  Abbay
//

import AppIntents
import Foundation

/// An author in the library, exposed to Siri and Shortcuts so one phrase can carry it: *"Play
/// Jane Austen in Abbay"* (#213). App Shortcut phrases interpolate only `AppEntity` and `AppEnum`
/// parameters, so before this an author-only request reached Abbay only through SiriKit's media
/// routing or a second turn of `PlayBookByNameIntent`.
///
/// The authors are the library's distinct artists. `SiriLibraryPublisher` refreshes them with the
/// books: its `updateAppShortcutParameters()` call re-reads every entity query's suggestions.
struct AuthorEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Author")
    static let defaultQuery = AuthorEntityQuery()

    /// The author as the library spells it (a book's `artist`).
    var id: String

    var name: String {
        id
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(name: String) {
        id = name
    }
}

/// The library's authors, and the book an author request plays.
enum LibraryAuthors {
    /// Distinct artists in library order, the last-played book's first; empty artists dropped. Two
    /// spellings that differ only in case or accents are one author, under the first spelling.
    static func all(in audios: [AudioModel], lastPlayedURL: URL?) -> [String] {
        var ordered = audios
        if let lastPlayedURL, let index = ordered.firstIndex(where: { $0.url == lastPlayedURL }) {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        var seen = Set<[String]>()
        return ordered.map { $0.artist.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(SpokenText.words($0)).inserted }
    }

    /// What *"Play \<author> in Abbay"* plays, by #207's rule: the author's last-played book, else
    /// their first in library order. The author's books are those whose artist is the author's
    /// name; if none is (the library changed since Siri fetched the entity), those `matchAuthor`
    /// finds.
    static func book(by author: String, in audios: [AudioModel], lastPlayedURL: URL?) -> AudioModel? {
        let name = SpokenText.words(author)
        let theirs = audios.filter { SpokenText.words($0.artist) == name }
        let found = theirs.isEmpty
            ? matchAuthor(input: author, audios: audios, lastPlayedURL: lastPlayedURL)
            : SpokenAuthor.pick(theirs, lastPlayedURL: lastPlayedURL)
        return found.first
    }
}

struct AuthorEntityQuery: EntityQuery, EntityStringQuery {
    /// Each author phrase expands once per suggestion, inside Apple's 1,000-phrase cap that the book
    /// and chapter phrases already fill most of (`AppShortcutPhraseTests`). Authors past it are
    /// still found by `entities(matching:)`.
    static let suggestionLimit = 15

    func entities(for identifiers: [AuthorEntity.ID]) async throws -> [AuthorEntity] {
        let known = Set(authors())
        return identifiers.filter(known.contains).map(AuthorEntity.init(name:))
    }

    func suggestedEntities() async throws -> [AuthorEntity] {
        let suggestions = authors().prefix(Self.suggestionLimit).map(AuthorEntity.init(name:))
        DependencyContainer.diagnostics.record("query author suggested count=\(suggestions.count)")
        return Array(suggestions)
    }

    /// What was said, read as an author by the matchers' rules (`matchAuthor`): the authors of the
    /// books it finds, in library order.
    func entities(matching string: String) async throws -> [AuthorEntity] {
        let library = AudiobookLibrary.all()
        let words = SpokenText.words(string)
        let author = SpokenAuthor.requested(in: words) ?? SpokenAuthor.bare(words)
        let books = SpokenAuthor.books(by: author, in: library)
        let names = LibraryAuthors.all(in: books, lastPlayedURL: nil)
        DependencyContainer.diagnostics.record("query author matching found=\(names.count)")
        return names.map(AuthorEntity.init(name:))
    }

    private func authors() -> [String] {
        LibraryAuthors.all(in: AudiobookLibrary.all(), lastPlayedURL: DependencyContainer.lastPlayed.lastPlayedURL())
    }
}
