//
//  AbbayIntents.swift
//  Abbay
//

import AppIntents
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
    let q = normalize(input)
    guard !q.isEmpty else { return nil }

    struct Scored {
        let audio: AudioModel
        let score: Int
        let isLastPlayed: Bool
        let index: Int
    }

    let scored: [Scored] = audios.enumerated().compactMap { idx, audio in
        let t = normalize(audio.title)
        let score: Int
        if t == q { score = 3 }
        else if t.hasPrefix(q) { score = 2 }
        else if t.contains(q) { score = 1 }
        else { score = 0 }
        guard score > 0 else { return nil }
        return Scored(audio: audio,
                      score: score,
                      isLastPlayed: audio.url != nil && audio.url == lastPlayedURL,
                      index: idx)
    }

    return scored.max { a, b in
        if a.score != b.score { return a.score < b.score }
        if a.isLastPlayed != b.isLastPlayed { return !a.isLastPlayed && b.isLastPlayed }
        return a.index > b.index
    }?.audio
}

/// Normalization for fuzzy-match comparison. Order is load-bearing:
///   1. Replace "&" with " and " (before stripping, otherwise & is lost)
///   2. Lowercase
///   3. Strip CharacterSet.punctuationCharacters ∪ .symbols
///   4. Collapse whitespace runs to a single space
///   5. Trim
private func normalize(_ s: String) -> String {
    var out = s.replacingOccurrences(of: "&", with: " and ")
    out = out.lowercased()
    let stripped = CharacterSet.punctuationCharacters.union(.symbols)
    out = String(out.unicodeScalars.filter { !stripped.contains($0) })
    let parts = out.split(whereSeparator: { $0.isWhitespace })
    return parts.joined(separator: " ")
}
