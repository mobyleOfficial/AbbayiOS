//
//  ChapterHeadingDetector.swift
//  Abbay
//

import Foundation

/// Finds chapters in a book's transcript by the headings its narrator reads out: "Chapter three",
/// "Part II", "Capítulo 4", "Prologue". Pure, so the rules are unit-tested without audio.
///
/// A heading is a heading keyword said **after a pause** (or as the book's first word), followed by
/// a number for the keywords that take one ("Chapter", "Part", "Book", "Section", "Volume" and their
/// Portuguese and Spanish words) or on its own for the ones that don't ("Prologue", "Epilogue",
/// "Introduction", "Preface"…). The pause is what tells "Chapter Two." at the start of a chapter
/// from "as we saw in chapter two" in a sentence, and a mention right after a full stop is still
/// only a mention unless the narrator stopped for it.
///
/// Headings closer together than `minimumChapterLength` are one heading. The same kind said again is
/// a repeat (a LibriVox chapter reads "Chapter 1 of Emma. This is a LibriVox recording… Chapter
/// 1."): the first wins. Another kind joins it ("Part One. The Tribute. Chapter one." is *Part One ·
/// Chapter One*), so a part's first chapter keeps its name. Audio before the
/// first heading is an opening chapter when it is longer than `openingThreshold`; a shorter lead-in
/// joins the first chapter. Fewer than `minimumHeadings` headings is no chapters at all: one stray
/// "Introduction" must not split a book in two.
enum ChapterHeadingDetector {
    /// Silence before a heading, in seconds.
    static let minimumPause = 1.0
    static let minimumChapterLength = 30.0
    static let openingThreshold = 30.0
    static let minimumHeadings = 2

    /// The book's chapters, sorted, the first starting at 0 and the last ending at `duration`;
    /// empty when the transcript doesn't hold enough headings.
    static func chapters(in lines: [ReadAlongLine], duration: Double, openingTitle: String) -> [ChapterModel] {
        let headings = headings(in: lines)
        guard headings.count >= minimumHeadings else { return [] }
        var starts: [(title: String, start: Double)] = headings.map { ($0.title, $0.start) }
        if starts[0].start > openingThreshold {
            starts.insert((openingTitle, 0), at: 0)
        } else {
            starts[0].start = 0
        }
        let end = max(duration, starts.last?.start ?? 0)
        return starts.indices.map { index in
            let next = index + 1 < starts.count ? starts[index + 1].start : end
            let start = starts[index].start
            return ChapterModel(title: starts[index].title, startTime: start, duration: next - start)
        }
    }

    /// A search continued from `chapters.last`'s start (#316): the chapters before stay as they are,
    /// and the headings in the new `lines` after that chapter's own (re-heard at the start) are
    /// added, each chapter running until the next and the last to `duration`. Unchanged when no
    /// new heading is heard.
    static func extending(_ chapters: [ChapterModel], with lines: [ReadAlongLine], duration: Double) -> [ChapterModel] {
        guard let last = chapters.last else { return [] }
        let new = headings(in: lines).filter { $0.start >= last.startTime + minimumChapterLength }
        let starts = chapters.map { (title: $0.title, start: $0.startTime) } + new
        let end = max(duration, starts.last?.start ?? 0)
        return starts.indices.map { index in
            let next = index + 1 < starts.count ? starts[index + 1].start : end
            let start = starts[index].start
            return ChapterModel(title: starts[index].title, startTime: start, duration: next - start)
        }
    }

    /// Every heading in the transcript, in order, with what to call it ("Chapter Three") and when
    /// its first word starts. A heading within `minimumChapterLength` of the one before is dropped
    /// when it is the same kind ("Chapter" again), and joins that one's title when it isn't.
    static func headings(in lines: [ReadAlongLine]) -> [(title: String, start: Double)] {
        /// A heading being collected, with the kinds of keyword it has joined.
        struct Found {
            var title: String
            let start: Double
            var kinds: Set<String>
        }
        let words = lines.sorted { $0.start < $1.start }.flatMap(\.words)
        var result: [Found] = []
        for index in words.indices {
            let isAfterPause = index == 0 || words[index].start - words[index - 1].end >= minimumPause
            guard isAfterPause, let title = heading(at: index, in: words) else { continue }
            let kind = normalised(words[index].text)
            if let last = result.last, words[index].start - last.start < minimumChapterLength {
                guard !last.kinds.contains(kind) else { continue }
                result[result.count - 1].title += " · " + title
                result[result.count - 1].kinds.insert(kind)
                continue
            }
            result.append(Found(title: title, start: words[index].start, kinds: [kind]))
        }
        return result.map { ($0.title, $0.start) }
    }

    /// The heading's title when `words[index]` starts one: the keyword and the number after it, as
    /// said ("Chapter Twenty-One", "Part II", "Capítulo Vinte e Dois"). Nil otherwise.
    static func heading(at index: Int, in words: [ReadAlongWord]) -> String? {
        let keyword = normalised(words[index].text)
        if standaloneKeywords.contains(keyword) {
            return displayed(words[index].text)
        }
        guard numberedKeywords.contains(keyword) else { return nil }
        // The number ends at the narrator's next pause ("Chapter 2. … One time, when I…"), and
        // nothing follows digits or a Roman numeral ("Chapter 15 I enter").
        var end = index + 1
        while end < words.count, isNumber(words[end].text, isFirst: end == index + 1),
              end == index + 1 || words[end].start - words[end - 1].end < minimumPause {
            end += 1
            if isNumeral(words[end - 1].text) { break }
        }
        // A trailing connector ("vinte e") isn't part of the number.
        while end > index + 1, connectors.contains(normalised(words[end - 1].text)) {
            end -= 1
        }
        guard end > index + 1 else { return nil }
        return words[index..<end].map { word in
            connectors.contains(normalised(word.text)) ? normalised(word.text) : displayed(word.text)
        }.joined(separator: " ")
    }

    // MARK: - Words

    /// Whether a word is a heading keyword ("Chapter", "Prólogo"): only then can new text hold a
    /// heading, and only then is the detector worth running again on a growing transcript.
    static func mayStartHeading(_ word: String) -> Bool {
        let keyword = normalised(word)
        return numberedKeywords.contains(keyword) || standaloneKeywords.contains(keyword)
    }

    /// Whether a word is (part of) a number: digits, a Roman numeral, a number word ("twenty-one"
    /// counts as one word), or, after the first, a connector ("vinte e um", "ciento y uno").
    private static func isNumber(_ word: String, isFirst: Bool) -> Bool {
        let parts = tokens(word)
        guard !parts.isEmpty else { return false }
        if !isFirst, parts.count == 1, connectors.contains(parts[0]) { return true }
        return parts.allSatisfy { part in
            part.allSatisfy(\.isNumber) || isRoman(part) || numberWords.contains(part)
        }
    }

    /// Digits or a Roman numeral: a whole number on its own.
    private static func isNumeral(_ word: String) -> Bool {
        let parts = tokens(word)
        return parts.count == 1 && (parts[0].allSatisfy(\.isNumber) || isRoman(parts[0]))
    }

    /// Lower-cased, without accents or punctuation: "Capítulo," is "capitulo".
    private static func normalised(_ word: String) -> String {
        tokens(word).joined()
    }

    private static func tokens(_ word: String) -> [String] {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Up to 89 (LXXXIX), the numerals a book's parts and chapters use, written the standard way.
    private static func isRoman(_ token: String) -> Bool {
        token.range(of: "^l?x{0,3}(ix|iv|v?i{0,3})$", options: .regularExpression) != nil && !token.isEmpty
    }

    /// As shown in the chapter list: without the punctuation around it, capitalised ("chapter" is
    /// "Chapter"), Roman numerals in capitals ("ii" is "II").
    private static func displayed(_ word: String) -> String {
        let trimmed = word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if isRoman(trimmed.lowercased()), !trimmed.isEmpty, trimmed.count <= 7 {
            return trimmed.uppercased()
        }
        return trimmed.split(separator: "-", omittingEmptySubsequences: false)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: "-")
    }

    // MARK: - Vocabulary (English, Portuguese, Spanish; without accents)

    private static let numberedKeywords: Set<String> = [
        "chapter", "part", "book", "section", "volume",
        "capitulo", "parte", "livro", "secao",
        "libro", "seccion", "tomo"
    ]

    private static let standaloneKeywords: Set<String> = [
        "prologue", "epilogue", "introduction", "preface", "foreword", "afterword", "prelude",
        "prologo", "epilogo", "introducao", "prefacio", "posfacio", "preludio",
        "introduccion"
    ]

    private static let connectors: Set<String> = ["and", "e", "y"]

    private static let numberWords: Set<String> = [
        // English
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
        "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty",
        "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred",
        "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
        "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth",
        "eighteenth", "nineteenth", "twentieth", "thirtieth", "fortieth", "fiftieth",
        // Portuguese
        "um", "uma", "dois", "duas", "tres", "quatro", "cinco", "seis", "sete", "oito", "nove", "dez",
        "onze", "doze", "treze", "catorze", "quatorze", "quinze", "dezesseis", "dezasseis", "dezessete",
        "dezassete", "dezoito", "dezenove", "dezanove", "vinte", "trinta", "quarenta", "cinquenta",
        "sessenta", "setenta", "oitenta", "noventa", "cem", "cento",
        "primeiro", "primeira", "segundo", "segunda", "terceiro", "terceira", "quarto", "quarta",
        "quinto", "quinta", "sexto", "sexta", "setimo", "setima", "oitavo", "oitava", "nono", "nona",
        "decimo", "decima",
        // Spanish
        "uno", "dos", "cuatro", "siete", "ocho", "nueve", "diez", "once", "doce", "trece", "catorce",
        "dieciseis", "diecisiete", "dieciocho", "diecinueve", "veinte", "veintiuno", "treinta", "cuarenta",
        "cincuenta", "sesenta", "ochenta", "cien", "ciento",
        "primero", "tercero", "tercera", "septimo", "septima", "octavo", "octava", "noveno", "novena"
    ]
}
