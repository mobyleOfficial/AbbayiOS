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
struct ChapterEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Chapter")
    static let defaultQuery = ChapterEntityQuery()

    /// Zero-based index into `AudioModel.chapters`.
    var id: Int

    /// Spoken/displayed position, one-based.
    var number: Int {
        id + 1
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource("siriChapterNumber", defaultValue: "Chapter \(number)"))
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
        let count = ChapterContext.currentBook()?.chapters.count ?? 0
        return identifiers.filter { $0 >= 0 && $0 < count }.map(ChapterEntity.init(id:))
    }

    func suggestedEntities() async throws -> [ChapterEntity] {
        let count = ChapterContext.currentBook()?.chapters.count ?? 0
        SiriDiagnostics.record("query chapter suggested count=\(min(count, Self.suggestionLimit))")
        return (0..<min(count, Self.suggestionLimit)).map(ChapterEntity.init(id:))
    }

    /// Siri hands over what the user said — "4", "chapter 4", or the chapter's own
    /// title. Digits win when present, otherwise fall back to a title match.
    func entities(matching string: String) async throws -> [ChapterEntity] {
        guard let book = ChapterContext.currentBook() else { return [] }
        let digits = string.filter(\.isNumber)
        if let spoken = Int(digits), spoken >= 1, spoken <= book.chapters.count {
            return [ChapterEntity(id: spoken - 1)]
        }
        let needle = string.lowercased()
        return book.chapters.enumerated()
            .filter { $0.element.title.lowercased().contains(needle) }
            .prefix(Self.suggestionLimit)
            .map { ChapterEntity(id: $0.offset) }
    }
}
