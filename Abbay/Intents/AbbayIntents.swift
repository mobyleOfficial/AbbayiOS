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

// MARK: - Resume

struct ResumeAbbayIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play in Abbay"
    static let description = IntentDescription("Resumes the last audiobook you played in Abbay.")

    init() {}

    // Spec-locked dialog text. v1 English-only (localization is a phase-2 non-goal).
    // Lifted into constants so a unit test catches regressions on wording / punctuation.
    static let addBookDialog = "Add a book in Abbay first."
    static let cannotFindDialog = "Cannot find that audiobook. It may have been removed or is not downloaded."
    static func playingDialog(title: String) -> String {
        "Playing \(title)."
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let url = LastPlayedStore.lastPlayedURL() else {
            return .result(dialog: IntentDialog(stringLiteral: Self.addBookDialog))
        }
        guard var model = DependencyContainer.shared.loadAudio.execute(url: url) else {
            // Stuck-state guard: don't loop on a dead pointer.
            LastPlayedStore.save(url: nil)
            return .result(dialog: IntentDialog(stringLiteral: Self.cannotFindDialog))
        }
        DependencyContainer.shared.player.play(&model)
        return .result(dialog: IntentDialog(stringLiteral: Self.playingDialog(title: model.title)))
    }
}
