//
//  FuzzyMatch.swift
//  Abbay
//
//  Extracted from AbbayIntents.swift (T19). Source-shared with the
//  AbbayIntents extension target so the extension's PlayMediaIntentHandler
//  can use the same matching rules as the phase-1 AppIntent path.
//

import Foundation

// MARK: - Fuzzy match helper

/// Returns the best library match for a spoken title, or nil if nothing matches.
/// See `matchAll` for the rules.
func fuzzyMatch(input: String,
                audios: [AudioModel],
                lastPlayedURL: URL?) -> AudioModel? {
    matchAll(input: input, audios: audios, lastPlayedURL: lastPlayedURL).first
}

/// Returns ALL audios tied at the top score (used by the extension's
/// `PlayMediaIntentHandler.resolveMediaItems` disambiguation path, the App Shortcuts entity
/// query and the iOS 27 audio domain).
/// Sort order: last-played first, then original library order.
///
/// What Siri hands over is what the person said, often with extra words: "the goblet of fire",
/// "harry potter and the goblet of fire by rowling", "o alienista por machado de assis" (#201).
/// Both sides are compared as words, case- and diacritic-insensitively, without articles and
/// other stop words (en and pt-BR, `SpokenText.stopWords`). Tiers, best first:
///
///   6 — the whole title, word for word
///   5 — the same words once stop words are dropped ("the goblet of fire" → "Goblet of Fire")
///   4 — the title starts with the query's words
///   3 — the title contains the query's words in a row
///   2 — the query contains the title's words in a row (titles of two words or more)
///   1 — the same words out of order: all the query's (two or more, half the title), or all the
///       title's (two or more)
///
/// "<title> by <author>" (pt-BR "por" or "de") is also tried as a title plus an author; a book
/// whose artist shares a word with the author ranks above the same tier without it. "Audiobook",
/// "book", "livro" at either end of the query are tried without them too. The best reading wins.
/// A word matches another when they are equal, or when the shorter has four letters or more and
/// starts the longer ("sorcerer" / "sorcerer's"), so "go" never matches "Goblet".
func matchAll(input: String,
              audios: [AudioModel],
              lastPlayedURL: URL?) -> [AudioModel] {
    let readings = SpokenQuery.readings(of: input)
    guard !readings.isEmpty else { return [] }

    struct ScoredMatch {
        let audio: AudioModel
        let score: Int
        let index: Int
    }

    let scored: [ScoredMatch] = audios.enumerated().compactMap { idx, audio in
        let book = SpokenBook(title: audio.title, artist: audio.artist)
        let score = readings.map { $0.score(against: book) }.max() ?? 0
        return score > 0 ? ScoredMatch(audio: audio, score: score, index: idx) : nil
    }

    guard let topScore = scored.map(\.score).max() else { return [] }

    let topMatches = scored.filter { $0.score == topScore }
    return topMatches.sorted { lhs, rhs in
        let lhsIsLast = lastPlayedURL.map { lhs.audio.url == $0 } ?? false
        let rhsIsLast = lastPlayedURL.map { rhs.audio.url == $0 } ?? false
        if lhsIsLast != rhsIsLast { return lhsIsLast }
        return lhs.index < rhs.index
    }.map(\.audio)
}

// MARK: - Internals

/// Word-level normalization shared by queries and titles.
enum SpokenText {
    /// Articles, prepositions and conjunctions in en and pt-BR. They carry no title identity, so a
    /// query made only of them ("the", "a", "de") matches nothing but a title that is exactly it.
    static let stopWords: Set<String> = [
        // en
        "a", "an", "the", "and", "of", "to", "in", "on", "at", "for", "by",
        // pt-BR
        "o", "os", "as", "um", "uma", "de", "do", "da", "dos", "das", "e", "em", "no", "na", "nos",
        "nas", "por"
    ]

    /// Words that can introduce the author: "<title> by <author>", "<título> por/de <autor>".
    static let authorMarkers: Set<String> = ["by", "por", "de"]

    /// Words people wrap around a title ("the audiobook X", "o livro X"). Dropped only at the
    /// query's ends, and only when something is left.
    static let fillerWords: Set<String> = ["audiobook", "audiobooks", "audio", "book", "audiolivro", "livro"]

    /// Lowercased, diacritic-folded words. Order is load-bearing: "&" becomes " and " before
    /// punctuation is stripped (otherwise "Tom&Jerry" would collapse to "tomjerry"), and
    /// apostrophes are stripped inside the word ("Don't" → "dont").
    static func words(_ text: String) -> [String] {
        let folded = text
            .replacingOccurrences(of: "&", with: " and ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
        let stripped = CharacterSet.punctuationCharacters.union(.symbols)
        let kept = String(folded.unicodeScalars.filter { !stripped.contains($0) })
        return kept.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    static func content(_ words: [String]) -> [String] {
        words.filter { !stopWords.contains($0) }
    }

    /// Equal, or the shorter (four letters or more) starts the longer.
    static func wordsMatch(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        guard min(lhs.count, rhs.count) >= 4 else { return false }
        return lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)
    }

    /// Where `needle` appears in `haystack` as a run of matching words, if it does.
    static func run(of needle: [String], in haystack: [String]) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        return (0...(haystack.count - needle.count)).first { start in
            zip(needle, haystack[start...]).allSatisfy { wordsMatch($0, $1) }
        }
    }
}

/// A library book as words.
struct SpokenBook {
    let words: [String]
    let content: [String]
    let artist: [String]

    init(title: String, artist: String) {
        words = SpokenText.words(title)
        content = SpokenText.content(words)
        self.artist = SpokenText.content(SpokenText.words(artist))
    }
}

/// One way of reading what was said: the words that name the title, and the author if one was
/// given.
struct SpokenQuery {
    let words: [String]
    let content: [String]
    let author: [String]

    /// Every reading of `input` worth scoring; empty when nothing was said.
    static func readings(of input: String) -> [SpokenQuery] {
        let words = SpokenText.words(input)
        guard !words.isEmpty else { return [] }
        // Every marker is a candidate split: titles hold "by" and "de" too ("Stand by Me",
        // "Memórias Póstumas de Brás Cubas"), and the unsplit reading is always scored as well.
        let markers = words.indices.dropFirst().dropLast().filter { SpokenText.authorMarkers.contains(words[$0]) }
        let splits = [(title: words, author: [String]())] + markers.map { marker in
            (title: Array(words[..<marker]), author: SpokenText.content(Array(words[(marker + 1)...])))
        }
        return splits.flatMap { split -> [SpokenQuery] in
            let content = SpokenText.content(split.title)
            let trimmed = withoutFiller(content)
            var readings = [SpokenQuery(words: split.title, content: content, author: split.author)]
            if trimmed != content {
                readings.append(SpokenQuery(words: trimmed, content: trimmed, author: split.author))
            }
            return readings
        }
    }

    private static func withoutFiller(_ content: [String]) -> [String] {
        var trimmed = content[...]
        while trimmed.count > 1, let first = trimmed.first, SpokenText.fillerWords.contains(first) {
            trimmed = trimmed.dropFirst()
        }
        while trimmed.count > 1, let last = trimmed.last, SpokenText.fillerWords.contains(last) {
            trimmed = trimmed.dropLast()
        }
        return Array(trimmed)
    }

    /// 0 when this reading doesn't name `book`. Otherwise the tier (see `matchAll`) in the
    /// thousands, plus 500 when the author matches the book's artist, plus the number of words
    /// that matched, so a closer match within a tier ranks first while equal ones still tie.
    func score(against book: SpokenBook) -> Int {
        guard let (tier, matched) = tier(against: book) else { return 0 }
        let authorMatches = author.contains { spoken in book.artist.contains { SpokenText.wordsMatch(spoken, $0) } }
        return tier * 1000 + (authorMatches ? 500 : 0) + min(matched, 499)
    }

    private func tier(against book: SpokenBook) -> (tier: Int, matched: Int)? {
        if words == book.words { return (6, words.count) }
        guard !content.isEmpty, !book.content.isEmpty else { return nil }
        if content.count == book.content.count, zip(content, book.content).allSatisfy(SpokenText.wordsMatch) {
            return (5, content.count)
        }
        if let start = SpokenText.run(of: content, in: book.content) {
            return (start == 0 ? 4 : 3, content.count)
        }
        if book.content.count >= 2, SpokenText.run(of: book.content, in: content) != nil {
            return (2, book.content.count)
        }
        return overlap(with: book).map { (1, $0) }
    }

    /// Shared words out of order, when they name the book rather than its series: every word
    /// said is in the title (two or more, covering half of it: "harry stone"), or every word of the
    /// title (two or more) was said. "harry potter goblet" therefore never falls back to another
    /// Harry Potter book: "goblet" is in neither its title nor a filler.
    private func overlap(with book: SpokenBook) -> Int? {
        let saidInTitle = content.filter { spoken in book.content.contains { SpokenText.wordsMatch(spoken, $0) } }.count
        let titleSaid = book.content.filter { word in content.contains { SpokenText.wordsMatch(word, $0) } }.count
        if saidInTitle == content.count, saidInTitle >= 2, titleSaid * 2 >= book.content.count {
            return saidInTitle
        }
        if titleSaid == book.content.count, titleSaid >= 2 {
            return titleSaid
        }
        return nil
    }
}
