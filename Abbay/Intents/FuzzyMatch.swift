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

/// Returns the best library match for a spoken title, or nil if no audio scores > 0.
///
/// Scoring (after `normalize`):
///   3 — exact equality
///   2 — title starts with input
///   1 — title contains input
///   0 — no overlap (filtered out)
///
/// Tie-break: an audio whose `url` equals `lastPlayedURL` is preferred over library order.
func fuzzyMatch(input: String,
                audios: [AudioModel],
                lastPlayedURL: URL?) -> AudioModel? {
    matchAll(input: input, audios: audios, lastPlayedURL: lastPlayedURL).first
}

/// Returns ALL audios tied at the top score (used by the extension's
/// `PlayMediaIntentHandler.resolveMediaItems` disambiguation path).
/// Sort order: last-played first, then original library order.
func matchAll(input: String,
              audios: [AudioModel],
              lastPlayedURL: URL?) -> [AudioModel] {
    let normalizedInput = fuzzyMatchNormalize(input)
    guard !normalizedInput.isEmpty else { return [] }

    let scored: [(AudioModel, Int, Int)] = audios.enumerated().compactMap { idx, audio in
        let score = fuzzyMatchScore(audio: audio, normalizedInput: normalizedInput)
        return score > 0 ? (audio, score, idx) : nil
    }

    guard let topScore = scored.map(\.1).max() else { return [] }

    let topMatches = scored.filter { $0.1 == topScore }
    return topMatches.sorted { lhs, rhs in
        let lhsIsLast = lastPlayedURL.map { lhs.0.url == $0 } ?? false
        let rhsIsLast = lastPlayedURL.map { rhs.0.url == $0 } ?? false
        if lhsIsLast != rhsIsLast { return lhsIsLast }
        return lhs.2 < rhs.2
    }.map { $0.0 }
}

// MARK: - Internals

/// Normalization for fuzzy-match comparison. Order is load-bearing:
///   1. Replace "&" with " and " (before stripping, otherwise & is lost)
///   2. Lowercase
///   3. Strip CharacterSet.punctuationCharacters ∪ .symbols
///   4. Collapse whitespace runs to a single space
///   5. Trim
private func fuzzyMatchNormalize(_ input: String) -> String {
    var out = input.replacingOccurrences(of: "&", with: " and ")
    out = out.lowercased()
    let stripped = CharacterSet.punctuationCharacters.union(.symbols)
    out = String(out.unicodeScalars.filter { !stripped.contains($0) })
    let parts = out.split(whereSeparator: { $0.isWhitespace })
    return parts.joined(separator: " ")
}

private func fuzzyMatchScore(audio: AudioModel, normalizedInput: String) -> Int {
    let normalizedTitle = fuzzyMatchNormalize(audio.title)
    if normalizedTitle == normalizedInput { return 3 }
    if normalizedTitle.hasPrefix(normalizedInput) { return 2 }
    if normalizedTitle.contains(normalizedInput) { return 1 }
    return 0
}
