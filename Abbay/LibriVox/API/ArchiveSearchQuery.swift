//
//  ArchiveSearchQuery.swift
//  Abbay
//

import Foundation

/// Builds the Lucene `q` for archive.org's advanced search.
///
/// LibriVox's own API has no fuzzy, substring or wildcard search, so the catalog is searched on
/// archive.org, which indexes every LibriVox recording in any language and folds diacritics.
enum ArchiveSearchQuery {
    /// LibriVox recordings only. `mediatype:audio` drops the collection's image and cover-art
    /// items, such as `LibrivoxM4bCollectionAudiobooksMain`.
    static let catalog = "collection:librivoxaudio AND mediatype:audio"

    /// The most-downloaded list: the whole catalog, sorted by the request.
    static let popular = catalog

    /// Lucene's special characters. `+` is not here: it can't be sent escaped (see `terms(in:)`).
    private static let specialCharacters = Set(#"-&|!(){}[]^"~*?:\/"#)

    /// Every term must match the title or the creator (archive.org's default is OR, which turns
    /// "the time machine" into half the catalog). The last term also matches as a prefix, so
    /// results keep up while the user is still typing a word. Nil when there's nothing to search.
    static func search(_ text: String) -> String? {
        var terms = terms(in: text)
        guard let last = terms.popLast() else { return nil }
        terms.append(last + "*")
        let clause = terms.joined(separator: " AND ")
        return "\(catalog) AND (title:(\(clause)) OR creator:(\(clause)))"
    }

    /// The session-cache key: two queries that build the same search share it.
    static func normalized(_ text: String) -> String {
        terms(in: text).joined(separator: " ")
    }

    /// Lowercased, so a typed AND/OR/NOT is a word and not an operator, with Lucene's special
    /// characters escaped. `+` is a separator: `URLComponents` leaves it unencoded and archive.org
    /// reads it as a space, so it can't reach Lucene as a literal anyway.
    static func terms(in text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "+", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { word in
                word.reduce(into: "") { escaped, character in
                    if specialCharacters.contains(character) { escaped.append("\\") }
                    escaped.append(character)
                }
            }
    }
}
