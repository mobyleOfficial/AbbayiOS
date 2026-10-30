//
//  ReadAlongLanguage.swift
//  Abbay
//

import Foundation

/// Pure helpers that turn LibriVox's language labels into codes, list the languages worth trying
/// when detecting what a book is read in, pick the most confident one, and name languages in the UI.
///
/// Locale ids are BCP-47 with a hyphen ("pt-BR"). Speech's `installedLocales` can report
/// underscores ("en_US"), so every input is normalised to hyphens first and every output uses them.
enum ReadAlongLanguage {
    // MARK: LibriVox labels

    /// LibriVox gives "eng", "English", "por", "Portuguese"…: a language code ("en"), or nil.
    static func languageCode(fromLibriVox value: String) -> String? {
        let label = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !label.isEmpty else { return nil }
        if let code = bibliographicCodes[label] { return code }
        if let code = namesToCodes[label] { return code }
        guard label.count <= 3, label.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return alpha2(Locale.LanguageCode(label))
    }

    /// The two-letter code, or nil for a language that has none: Foundation answers with the
    /// three-letter code itself ("tlh" for Klingon), which no speech model is keyed by.
    private static func alpha2(_ language: Locale.LanguageCode) -> String? {
        guard let code = language.identifier(.alpha2), code.count == 2 else { return nil }
        return code
    }

    /// The ISO 639-2/B codes LibriVox uses that differ from the terminological ones Foundation knows
    /// ("ger" rather than "deu").
    private static let bibliographicCodes: [String: String] = [
        "alb": "sq", "arm": "hy", "baq": "eu", "bur": "my", "chi": "zh", "cze": "cs", "dut": "nl",
        "fre": "fr", "geo": "ka", "ger": "de", "gre": "el", "ice": "is", "mac": "mk", "mao": "mi",
        "may": "ms", "per": "fa", "rum": "ro", "slo": "sk", "tib": "bo", "wel": "cy"
    ]

    /// Lower-cased English language names to their codes, built once from Foundation's own list.
    private static let namesToCodes: [String: String] = {
        let english = Locale(identifier: "en")
        var result: [String: String] = [:]
        for language in Locale.LanguageCode.isoLanguageCodes {
            guard let code = alpha2(language),
                  let name = english.localizedString(forLanguageCode: code)
            else { continue }
            result[name.lowercased()] = code
        }
        return result
    }()

    // MARK: Candidates

    /// Candidate locale ids for detection, in order, deduplicated, only ones in `installed`:
    /// the app language, then `preferred` (device), then English.
    ///
    /// `appLanguage` is a bare code ("pt") or nil for the system language. A bare code takes the
    /// region of the first `preferred` entry in that language, so "pt" with a Brazilian device is
    /// "pt-BR", not "pt-PT". A full preferred id must be installed as written, else its language
    /// stands in for it.
    static func candidates(appLanguage: String?, preferred: [String], installed: [String]) -> [String] {
        let installed = installed.map(normalised)
        let preferred = preferred.map(normalised)
        var result: [String] = []
        func add(_ locale: String?) {
            if let locale, !result.contains(locale) { result.append(locale) }
        }

        if let appLanguage {
            let code = parts(of: appLanguage).language
            let region = preferred.lazy.map(parts(of:)).first { $0.language == code && $0.region != nil }?.region
            add(locale(forLanguageCode: code, in: installed, preferredRegion: region))
        }
        for id in preferred {
            if let exact = installed.first(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) {
                add(exact)
            } else {
                add(locale(forLanguageCode: parts(of: id).language, in: installed, preferredRegion: nil))
            }
        }
        add(locale(forLanguageCode: "en", in: installed, preferredRegion: nil))
        return result
    }

    /// The supported locale that matches a language code ("pt" → "pt-BR" if offered), in order:
    /// the one in `preferredRegion` (the device's own, for that language); else an `installed` one,
    /// so a model already on the device is used rather than another region's download; else the
    /// language's likely region ("en" → US, "pt" → BR, "es" → ES); else the first of that language.
    /// Never the alphabetically first by default: that is en-AU for English.
    static func locale(
        forLanguageCode code: String,
        in supported: [String],
        installed: [String] = [],
        preferredRegion: String?
    ) -> String? {
        let code = code.lowercased()
        let matches = supported.map(normalised).filter { parts(of: $0).language == code }
        let likely = likelyRegion(of: code)
        func inRegion(_ region: String?, among locales: [String]) -> String? {
            guard let region else { return nil }
            return locales.first { parts(of: $0).region?.caseInsensitiveCompare(region) == .orderedSame }
        }
        let installed = Set(installed.map { normalised($0).lowercased() })
        let installedMatches = matches.filter { installed.contains($0.lowercased()) }
        return inRegion(preferredRegion, among: matches)
            ?? inRegion(likely, among: installedMatches)
            ?? installedMatches.first
            ?? inRegion(likely, among: matches)
            ?? matches.first
    }

    /// The region a language is most likely spoken in, from CLDR's likely subtags ("en" is
    /// "en-Latn-US").
    private static func likelyRegion(of code: String) -> String? {
        parts(of: Locale.Language(identifier: code).maximalIdentifier).region
    }

    // MARK: Detection pick

    /// The locale with the best mean confidence, if it reaches `minimumConfidence`; else nil.
    /// Ties go to the alphabetically first id so a re-run picks the same language.
    static func best(_ scores: [String: Double], minimumConfidence: Double = 0.5) -> String? {
        guard let top = scores.min(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }),
              top.value >= minimumConfidence
        else { return nil }
        return top.key
    }

    // MARK: Names

    /// "English", "Português" in the in-app language (`AbbayBundle.locale`). The language only, not
    /// the region: the picker lists languages, and the region is a detail of the speech model.
    static func displayName(_ localeID: String, in locale: Locale = AbbayBundle.locale) -> String {
        let code = parts(of: localeID).language
        guard let name = locale.localizedString(forLanguageCode: code) else { return localeID }
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }

    // MARK: Identifiers

    private static func normalised(_ id: String) -> String {
        id.replacingOccurrences(of: "_", with: "-")
    }

    /// The lower-cased language and, if present, the region (two letters or three digits) of an id.
    private static func parts(of id: String) -> (language: String, region: String?) {
        let components = normalised(id).split(separator: "-").map(String.init)
        let region = components.dropFirst().first {
            ($0.count == 2 && $0.allSatisfy(\.isLetter)) || ($0.count == 3 && $0.allSatisfy(\.isNumber))
        }
        return (components.first?.lowercased() ?? "", region)
    }
}
