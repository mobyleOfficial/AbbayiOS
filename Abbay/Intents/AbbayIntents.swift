//
//  AbbayIntents.swift
//  Abbay
//

import AppIntents
import Foundation

// MARK: - Shared dialogs

/// Spoken when the audio session is unavailable (e.g. another app holds it during a phone call).
/// Phase-2 contract: dialog text is locked to enable manual verification + regression tests.
let abbayAudioUnavailableDialog = "Audio temporarily unavailable. Try again in a moment."

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
    let query = normalize(input)
    guard !query.isEmpty else { return nil }

    struct Scored {
        let audio: AudioModel
        let score: Int
        let isLastPlayed: Bool
        let index: Int
    }

    let scored: [Scored] = audios.enumerated().compactMap { idx, audio in
        let normalizedTitle = normalize(audio.title)
        let score: Int
        if normalizedTitle == query {
            score = 3
        } else if normalizedTitle.hasPrefix(query) {
            score = 2
        } else if normalizedTitle.contains(query) {
            score = 1
        } else {
            score = 0
        }
        guard score > 0 else { return nil }
        return Scored(
            audio: audio,
            score: score,
            isLastPlayed: audio.url != nil && audio.url == lastPlayedURL,
            index: idx
        )
    }

    return scored.max { lhs, rhs in
        if lhs.score != rhs.score { return lhs.score < rhs.score }
        if lhs.isLastPlayed != rhs.isLastPlayed { return !lhs.isLastPlayed && rhs.isLastPlayed }
        return lhs.index > rhs.index
    }?.audio
}

/// Normalization for fuzzy-match comparison. Order is load-bearing:
///   1. Replace "&" with " and " (before stripping, otherwise & is lost)
///   2. Lowercase
///   3. Strip CharacterSet.punctuationCharacters ∪ .symbols
///   4. Collapse whitespace runs to a single space
///   5. Trim
private func normalize(_ input: String) -> String {
    var out = input.replacingOccurrences(of: "&", with: " and ")
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

    // Spec-locked dialog text. v1 English-only (localization is a phase-2 non-goal).
    // Lifted into constants so a unit test catches regressions on wording / punctuation.
    static let addBookDialog = "Add a book in Abbay first."
    static let cannotFindDialog = "Cannot find that audiobook. It may have been removed or is not downloaded."

    static func playingDialog(title: String) -> String {
        "Playing \(title)."
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !LaunchStateFlag.isUnavailable() else {
            return .result(dialog: IntentDialog(stringLiteral: abbayAudioUnavailableDialog))
        }
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

// MARK: - Pause

struct PauseAbbayIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Pause Abbay"
    static let description = IntentDescription("Pauses the current audiobook in Abbay.")

    static let nothingPlayingDialog = "Nothing is playing."
    static let pausedDialog = "Paused."

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !LaunchStateFlag.isUnavailable() else {
            return .result(dialog: IntentDialog(stringLiteral: abbayAudioUnavailableDialog))
        }
        guard NowPlayingManager.shared.currentAudio != nil else {
            return .result(dialog: IntentDialog(stringLiteral: Self.nothingPlayingDialog))
        }
        DependencyContainer.shared.player.pause()
        return .result(dialog: IntentDialog(stringLiteral: Self.pausedDialog))
    }
}

// MARK: - Next chapter

struct NextChapterIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next chapter in Abbay"
    static let description = IntentDescription("Skips to the next chapter of the audiobook playing in Abbay.")

    static let nothingPlayingDialog = "Nothing is playing. Say 'Play in Abbay' to start."
    static let nextChapterDialog = "Next chapter."

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !LaunchStateFlag.isUnavailable() else {
            return .result(dialog: IntentDialog(stringLiteral: abbayAudioUnavailableDialog))
        }
        guard NowPlayingManager.shared.currentAudio != nil else {
            return .result(dialog: IntentDialog(stringLiteral: Self.nothingPlayingDialog))
        }
        DependencyContainer.shared.player.skipToNextChapter()
        return .result(dialog: IntentDialog(stringLiteral: Self.nextChapterDialog))
    }
}

// MARK: - Previous chapter

struct PreviousChapterIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous chapter in Abbay"
    static let description = IntentDescription("Skips to the previous chapter of the audiobook playing in Abbay.")

    static let nothingPlayingDialog = "Nothing is playing. Say 'Play in Abbay' to start."
    static let previousChapterDialog = "Previous chapter."

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !LaunchStateFlag.isUnavailable() else {
            return .result(dialog: IntentDialog(stringLiteral: abbayAudioUnavailableDialog))
        }
        guard NowPlayingManager.shared.currentAudio != nil else {
            return .result(dialog: IntentDialog(stringLiteral: Self.nothingPlayingDialog))
        }
        DependencyContainer.shared.player.skipToPreviousChapter()
        return .result(dialog: IntentDialog(stringLiteral: Self.previousChapterDialog))
    }
}

// MARK: - Play book by name

struct PlayBookByNameIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play audiobook in Abbay"
    static let description = IntentDescription("Plays a specific audiobook in Abbay by name.")

    @Parameter(title: "Audiobook", requestValueDialog: IntentDialog("Which audiobook?"))
    var bookName: String

    // Spec-locked dialog text. v1 ships English only (non-goal: localization).
    // Lift into constants so a unit test catches regressions on wording / punctuation.
    static func noMatchDialog(_ input: String) -> String {
        "No audiobook matches '\(input)'."
    }

    static let cannotFindDialog = "Cannot find that audiobook. It may have been removed or is not downloaded."

    static func playingDialog(title: String) -> String {
        "Playing \(title)."
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !LaunchStateFlag.isUnavailable() else {
            return .result(dialog: IntentDialog(stringLiteral: abbayAudioUnavailableDialog))
        }
        let library = DependencyContainer.shared.loadAllAudios.execute()
        let lastPlayed = LastPlayedStore.lastPlayedURL()
        guard let hit = fuzzyMatch(input: bookName, audios: library, lastPlayedURL: lastPlayed),
              let url = hit.url else {
            return .result(dialog: IntentDialog(stringLiteral: Self.noMatchDialog(bookName)))
        }
        guard var model = DependencyContainer.shared.loadAudio.execute(url: url) else {
            // Stuck-state guard: clear pointer only if the dead match is the saved one.
            if LastPlayedStore.lastPlayedURL() == url {
                LastPlayedStore.save(url: nil)
            }
            return .result(dialog: IntentDialog(stringLiteral: Self.cannotFindDialog))
        }
        DependencyContainer.shared.player.play(&model)
        return .result(dialog: IntentDialog(stringLiteral: Self.playingDialog(title: model.title)))
    }
}

// MARK: - App Shortcuts (phrase registration)

struct AbbayAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResumeAbbayIntent(),
            phrases: [
                "Play in \(.applicationName)",
                "Resume \(.applicationName)",
                "Continue audiobook in \(.applicationName)"
            ],
            shortTitle: "Play",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PauseAbbayIntent(),
            phrases: [
                "Pause \(.applicationName)"
            ],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: NextChapterIntent(),
            phrases: [
                "Next chapter in \(.applicationName)",
                "Skip chapter in \(.applicationName)"
            ],
            shortTitle: "Next chapter",
            systemImageName: "forward.fill"
        )
        AppShortcut(
            intent: PreviousChapterIntent(),
            phrases: [
                "Previous chapter in \(.applicationName)"
            ],
            shortTitle: "Previous chapter",
            systemImageName: "backward.fill"
        )
        // PlayBookByNameIntent.bookName is `String`, which AppIntents disallows in
        // `\(\.$bookName)` phrase interpolations (the toolchain rejects with "AppEntity
        // and AppEnum are the only allowed types"). The v1 design (plan Task 7) keeps
        // the parameter as String to preserve the spec-locked no-match dialog with
        // input echo (`"No audiobook matches '\(input)'."`). The trade-off: Siri
        // routes a parameter-less phrase like "Play audiobook in Abbay", then prompts
        // "Which audiobook?" via `requestValueDialog`, and the user names the book in
        // a second utterance. The String parameter still flows into perform().
        AppShortcut(
            intent: PlayBookByNameIntent(),
            phrases: [
                "Play audiobook in \(.applicationName)",
                "Pick audiobook in \(.applicationName)"
            ],
            shortTitle: "Play audiobook",
            systemImageName: "book.fill"
        )
    }
}
