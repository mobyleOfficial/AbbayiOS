//
//  ChapterEntity.swift
//  Abbay
//

import AppIntents
import Foundation

/// A chapter of the book Siri is most likely to act on — the one playing now, or
/// the last-played one when nothing is loaded.
///
/// Chapters are timestamps inside a single audio file, not separate tracks, so a
/// chapter is addressed by its position in the current book rather than by a URL.
///
/// It shows, and Siri reads back, the number "chapter N" names it by (`ChapterNumbering`, #212):
/// in a book that opens with a prologue the second chapter is *Chapter 1*, and the prologue shows
/// its title. The App Shortcut phrases expand to these, so "Play Chapter 1 in Abbay" lands where
/// `matchChapters` would.
struct ChapterEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Chapter")
    static let defaultQuery = ChapterEntityQuery()

    /// Zero-based index into `AudioModel.chapters`.
    var id: Int

    /// The number the chapter is asked for by; nil for front and back matter ("Prologue").
    var number: Int?

    /// The chapter's title, shown when it has no number.
    var title: String

    /// What the dialogs say: the number, or the position when there is none.
    var spokenNumber: Int {
        number ?? id + 1
    }

    var displayRepresentation: DisplayRepresentation {
        if number == nil, !title.isEmpty {
            return DisplayRepresentation(title: "\(title)")
        }
        return DisplayRepresentation(
            title: LocalizedStringResource("siriChapterNumber", defaultValue: "Chapter \(spokenNumber)")
        )
    }

    /// A chapter numbered by its position, for callers without the book's titles.
    init(id: Int) {
        self.init(id: id, number: id + 1, title: "")
    }

    init(id: Int, number: Int?, title: String) {
        self.id = id
        self.number = number
        self.title = title
    }

    /// The book's chapters as entities, numbered as `ChapterNumbering` numbers them.
    static func all(in book: AudioModel) -> [ChapterEntity] {
        let titles = book.chapters.map(\.title)
        let numbers = ChapterNumbering(titles: titles).numbers
        return titles.indices.map { ChapterEntity(id: $0, number: numbers[$0], title: titles[$0]) }
    }
}

/// Resolves the book whose chapters Siri should offer: what is playing now, else
/// the last-played pointer.
enum ChapterContext {
    static func currentBook() -> AudioModel? {
        if let playing = NowPlayingManager.shared.currentAudio, !playing.chapters.isEmpty {
            return playing
        }
        guard DependencyContainer.isConfigured,
              let url = DependencyContainer.shared.lastPlayed.lastPlayedURL() else {
            return nil
        }
        return DependencyContainer.shared.loadAudio.execute(url: url)
    }
}

struct ChapterEntityQuery: EntityQuery, EntityStringQuery {
    /// Phrase-budget cap, same reasoning as `AudiobookEntityQuery.suggestionLimit`.
    static let suggestionLimit = 50

    func entities(for identifiers: [ChapterEntity.ID]) async throws -> [ChapterEntity] {
        let chapters = ChapterContext.currentBook().map(ChapterEntity.all(in:)) ?? []
        return identifiers.filter(chapters.indices.contains).map { chapters[$0] }
    }

    func suggestedEntities() async throws -> [ChapterEntity] {
        let chapters = ChapterContext.currentBook().map(ChapterEntity.all(in:)) ?? []
        DependencyContainer.diagnostics.record("query chapter suggested count=\(min(chapters.count, Self.suggestionLimit))")
        return Array(chapters.prefix(Self.suggestionLimit))
    }

    /// Siri hands over what the user said: "4", "chapter four", "o terceiro capítulo", or the
    /// chapter's own title with extra words. A spoken number wins, then the title rules shared
    /// with book titles (`matchChapters`, #206); the number is the chapter's own (#212).
    func entities(matching string: String) async throws -> [ChapterEntity] {
        guard let book = ChapterContext.currentBook() else { return [] }
        let chapters = ChapterEntity.all(in: book)
        return matchChapters(input: string, titles: book.chapters.map(\.title))
            .prefix(Self.suggestionLimit)
            .map { chapters[$0] }
    }
}
