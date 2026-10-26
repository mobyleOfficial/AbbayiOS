//
//  LibraryFilter.swift
//  Abbay
//

import Foundation

/// The Library's local search: matches a book's title or author, ignoring case and diacritics
/// ("memorias" finds "Memórias"). It never touches the network. A blank query keeps every book.
enum LibraryFilter {
    static func filter(_ books: [AudioModel], query: String) -> [AudioModel] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return books }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return books.filter {
            $0.title.range(of: text, options: options) != nil || $0.artist.range(of: text, options: options) != nil
        }
    }
}
