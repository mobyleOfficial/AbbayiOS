//
//  ChapterMatch.swift
//  Abbay
//

import Foundation

/// The chapters (zero-based positions) that `input` names among `titles`, best first; empty when
/// none does. Siri hands over what was said: "4", "chapter 4", "chapter four", "o terceiro
/// capítulo", or the chapter's own title with extra words ("the prologue chapter", "o capítulo
/// prólogo", #206). In order:
///
/// 1. A position said as a number: digits ("4", "capítulo 3", "3rd"), or number words next to
///    "chapter"/"capítulo" ("chapter three", "capítulo vinte e um", "the third chapter"). Spoken
///    positions count from one; one past the book falls through to the titles ("1984").
/// 2. The titles, by the book-title rules of `matchAll` (folding, en and pt-BR stop words, word
///    overlap, `SpokenQuery`), with "chapter"/"capítulo" dropped at either end. Every chapter tied
///    at the top score is returned, in book order. "chapter" or stop words alone name no chapter
///    unless a title is exactly that.
/// 3. Number words on their own ("three"), when no title has them.
/// 4. The one number in an otherwise unmatched request ("play chapter 4 please").
func matchChapters(input: String, titles: [String]) -> [Int] {
    let words = SpokenText.words(input)
    guard !words.isEmpty, !titles.isEmpty else { return [] }
    let spoken = SpokenChapterNumber(words: words)
    let inBook = { (number: Int?) -> [Int]? in
        number.flatMap { titles.indices.contains($0 - 1) ? [$0 - 1] : nil }
    }
    if let position = inBook(spoken.explicit) { return position }
    let byTitle = matchChapterTitles(words: words, input: input, titles: titles)
    if !byTitle.isEmpty { return byTitle }
    return inBook(spoken.bare) ?? inBook(spoken.loose) ?? []
}

/// Tier 2 of `matchChapters`.
private func matchChapterTitles(words: [String], input: String, titles: [String]) -> [Int] {
    let content = SpokenText.content(words).filter { !SpokenChapterNumber.chapterWords.contains($0) }
    guard !content.isEmpty else {
        return titles.indices.filter { SpokenText.words(titles[$0]) == words }
    }
    let fillers = SpokenText.fillerWords.union(SpokenChapterNumber.chapterWords)
    let readings = SpokenQuery.readings(of: input, fillers: fillers)
    let scores = titles.map { title in
        let chapter = SpokenBook(title: title, artist: "")
        return readings.map { $0.score(against: chapter) }.max() ?? 0
    }
    guard let top = scores.max(), top > 0 else { return [] }
    return scores.indices.filter { scores[$0] == top }
}

/// A chapter position said aloud, en and pt-BR.
struct SpokenChapterNumber {
    /// Words that say "chapter". Folded, so "capítulo" is "capitulo".
    static let chapterWords: Set<String> = ["chapter", "chapters", "capitulo", "capitulos"]

    /// Words around a number that don't change it: "the third chapter", "o capítulo número 3".
    static let ignoredWords: Set<String> = ["the", "o", "a", "os", "as", "no", "na", "number", "numero", "n"]

    /// Digits, or number words next to "chapter": the position wins over any title.
    let explicit: Int?
    /// Number words alone ("three"): a position only when no title has the words.
    let bare: Int?
    /// The only number among other words: a position when nothing else matched.
    let loose: Int?

    init(words: [String]) {
        let saysChapter = words.contains(where: Self.chapterWords.contains)
        let rest = words.filter { !Self.chapterWords.contains($0) && !Self.ignoredWords.contains($0) }
        let digits = rest.count == 1 ? Self.digits(rest[0]) : nil
        let spelled = Self.spelled(rest)
        explicit = digits ?? (saysChapter ? spelled : nil)
        bare = saysChapter ? nil : spelled
        let numbers = words.compactMap(Self.digits)
        loose = numbers.count == 1 ? numbers[0] : nil
    }

    /// "4", "3rd", "21st", "3o" (pt-BR "3º"; "º" folds to "o").
    static func digits(_ word: String) -> Int? {
        let number = word.prefix { $0.isASCII && $0.isNumber }
        guard !number.isEmpty else { return nil }
        let suffix = word.dropFirst(number.count)
        guard ["", "st", "nd", "rd", "th", "o", "a", "\u{BA}", "\u{AA}"].contains(String(suffix)) else { return nil }
        return Int(number)
    }

    /// One to ninety-nine in words, cardinal or ordinal, en and pt-BR: "three", "twenty one",
    /// "twenty-one" (punctuation is stripped, so "twentyone"), "vinte e um", "décimo primeiro".
    static func spelled(_ words: [String]) -> Int? {
        let parts = words.filter { $0 != "and" && $0 != "e" }.flatMap(split)
        switch parts.count {
        case 1:
            return value(parts[0])?.number
        case 2:
            guard let tens = value(parts[0]), tens.kind == .tens,
                  let unit = value(parts[1]), unit.kind == .unit else { return nil }
            return tens.number + unit.number
        default:
            return nil
        }
    }

    private enum Kind { case unit, teen, tens }

    private static func value(_ word: String) -> (number: Int, kind: Kind)? {
        if let number = units[word] { return (number, .unit) }
        if let number = teens[word] { return (number, .teen) }
        if let number = tens[word] { return (number, .tens) }
        return nil
    }

    /// "twentyone" → "twenty", "one". Other words stay as they are.
    private static func split(_ word: String) -> [String] {
        guard value(word) == nil else { return [word] }
        for prefix in tens.keys where word.hasPrefix(prefix) {
            let unit = String(word.dropFirst(prefix.count))
            if units[unit] != nil { return [prefix, unit] }
        }
        return [word]
    }

    private static let units: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7,
        "eighth": 8, "ninth": 9,
        "um": 1, "uma": 1, "dois": 2, "duas": 2, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6,
        "sete": 7, "oito": 8, "nove": 9,
        "primeiro": 1, "primeira": 1, "segundo": 2, "segunda": 2, "terceiro": 3, "terceira": 3,
        "quarto": 4, "quarta": 4, "quinto": 5, "quinta": 5, "sexto": 6, "sexta": 6, "setimo": 7,
        "setima": 7, "oitavo": 8, "oitava": 8, "nono": 9, "nona": 9
    ]

    private static let teens: [String: Int] = [
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14, "fifteenth": 15,
        "sixteenth": 16, "seventeenth": 17, "eighteenth": 18, "nineteenth": 19,
        "onze": 11, "doze": 12, "treze": 13, "catorze": 14, "quatorze": 14, "quinze": 15,
        "dezesseis": 16, "dezessete": 17, "dezoito": 18, "dezenove": 19
    ]

    /// Tens, which a unit may follow. "Décimo" is here because pt-BR builds 11th to 19th on it
    /// ("décimo primeiro").
    private static let tens: [String: Int] = [
        "ten": 10, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
        "eighty": 80, "ninety": 90,
        "tenth": 10, "twentieth": 20, "thirtieth": 30, "fortieth": 40, "fiftieth": 50,
        "dez": 10, "vinte": 20, "trinta": 30, "quarenta": 40, "cinquenta": 50, "sessenta": 60,
        "setenta": 70, "oitenta": 80, "noventa": 90,
        "decimo": 10, "decima": 10, "vigesimo": 20, "vigesima": 20, "trigesimo": 30, "trigesima": 30
    ]
}
