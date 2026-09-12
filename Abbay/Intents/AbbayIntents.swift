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
        // Attempt audio session activation. If it succeeds, clears the flag (so a
        // stale `true` from a previous cold-launch failure no longer sticks). If
        // it still throws, sets the flag and exits with the unavailable dialog.
        guard AudioSessionActivator.attemptActivation() else {
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
        // Attempt audio session activation. If it succeeds, clears the flag (so a
        // stale `true` from a previous cold-launch failure no longer sticks). If
        // it still throws, sets the flag and exits with the unavailable dialog.
        guard AudioSessionActivator.attemptActivation() else {
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
        // Attempt audio session activation. If it succeeds, clears the flag (so a
        // stale `true` from a previous cold-launch failure no longer sticks). If
        // it still throws, sets the flag and exits with the unavailable dialog.
        guard AudioSessionActivator.attemptActivation() else {
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
        // Attempt audio session activation. If it succeeds, clears the flag (so a
        // stale `true` from a previous cold-launch failure no longer sticks). If
        // it still throws, sets the flag and exits with the unavailable dialog.
        guard AudioSessionActivator.attemptActivation() else {
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
        // Attempt audio session activation. If it succeeds, clears the flag (so a
        // stale `true` from a previous cold-launch failure no longer sticks). If
        // it still throws, sets the flag and exits with the unavailable dialog.
        guard AudioSessionActivator.attemptActivation() else {
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

// MARK: - Play a specific audiobook (one-shot, entity parameter)

/// One-utterance "Play <title> in Abbay".
///
/// Unlike `PlayBookByNameIntent` (a `String` parameter, which AppIntents refuses
/// to interpolate into a spoken phrase and therefore always costs a second
/// "Which audiobook?" turn), this intent takes an `AudiobookEntity`, so the title
/// can live inside the phrase itself.
struct PlayAudiobookIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play audiobook"
    static let description = IntentDescription("Plays one of your Abbay audiobooks by name.")

    @Parameter(title: "Audiobook")
    var audiobook: AudiobookEntity

    static let cannotFindDialog = "Cannot find that audiobook. It may have been removed or is not downloaded."

    static func playingDialog(title: String) -> String {
        "Playing \(title)."
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard AudioSessionActivator.attemptActivation() else {
            return .result(dialog: IntentDialog(stringLiteral: abbayAudioUnavailableDialog))
        }
        guard let url = audiobook.url,
              var model = DependencyContainer.shared.loadAudio.execute(url: url) else {
            // Stuck-state guard: clear the pointer only if the dead book is the saved one.
            if let url = audiobook.url, LastPlayedStore.lastPlayedURL() == url {
                LastPlayedStore.save(url: nil)
            }
            return .result(dialog: IntentDialog(stringLiteral: Self.cannotFindDialog))
        }
        DependencyContainer.shared.player.play(&model)
        return .result(dialog: IntentDialog(stringLiteral: Self.playingDialog(title: model.title)))
    }
}

// MARK: - Play a specific chapter

/// "Play chapter 4 in Abbay". Acts on the book that is playing, or resumes the
/// last-played book positioned at the requested chapter when nothing is loaded.
struct PlayChapterIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play chapter"
    static let description = IntentDescription("Jumps to a chapter of the audiobook you are listening to.")

    @Parameter(title: "Chapter")
    var chapter: ChapterEntity

    static let nothingToPlayDialog = "Nothing to play. Say 'Play in Abbay' to start a book."

    static func noChapterDialog(_ number: Int) -> String {
        "That audiobook doesn't have a chapter \(number)."
    }

    static func playingChapterDialog(_ number: Int) -> String {
        "Playing chapter \(number)."
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard AudioSessionActivator.attemptActivation() else {
            return .result(dialog: IntentDialog(stringLiteral: abbayAudioUnavailableDialog))
        }
        let index = chapter.id

        // Already listening: a seek is enough, and it avoids reloading the item.
        if NowPlayingManager.shared.currentAudio != nil,
           DependencyContainer.shared.player.playChapter(at: index) {
            return .result(dialog: IntentDialog(stringLiteral: Self.playingChapterDialog(chapter.number)))
        }

        // Cold: resume the last-played book, but start it at the requested chapter.
        // Setting `currentTime` before `play` avoids racing the seek against
        // AVPlayerItem loading.
        guard let url = LastPlayedStore.lastPlayedURL(),
              var model = DependencyContainer.shared.loadAudio.execute(url: url) else {
            return .result(dialog: IntentDialog(stringLiteral: Self.nothingToPlayDialog))
        }
        guard model.chapters.indices.contains(index) else {
            return .result(dialog: IntentDialog(stringLiteral: Self.noChapterDialog(chapter.number)))
        }
        model.currentTime = model.chapters[index].startTime
        DependencyContainer.shared.player.play(&model)
        return .result(dialog: IntentDialog(stringLiteral: Self.playingChapterDialog(chapter.number)))
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
            intent: PlayAudiobookIntent(),
            phrases: [
                "Play \(\.$audiobook) in \(.applicationName)",
                "Open \(\.$audiobook) in \(.applicationName)",
                "Listen to \(\.$audiobook) in \(.applicationName)"
            ],
            shortTitle: "Play audiobook",
            systemImageName: "books.vertical.fill"
        )
        AppShortcut(
            intent: PlayChapterIntent(),
            phrases: [
                "Play \(\.$chapter) in \(.applicationName)",
                "Skip to \(\.$chapter) in \(.applicationName)"
            ],
            shortTitle: "Play chapter",
            systemImageName: "list.number"
        )
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
