//
//  AbbayIntents.swift
//  Abbay
//

import AppIntents
import Foundation

// MARK: - Shared dialogs

// Every dialog is a `LocalizedStringResource`, not a `String`. Siri receives the resource and
// resolves it in the user's Siri language, from `Localizable.xcstrings` in the app bundle (App
// Intents run in the app process, so `.main` is the right bundle). Keys are explicit so a wording
// tweak doesn't orphan the translations; `defaultValue` is the English text.
// Dialog text is spec-locked in both languages, and lifted into constants so a unit test catches
// regressions on wording / punctuation.

/// Spoken when the audio session is unavailable (e.g. another app holds it during a phone call).
let abbayAudioUnavailableDialog = LocalizedStringResource(
    "siriAudioUnavailable",
    defaultValue: "Audio temporarily unavailable. Try again in a moment."
)

/// Shared by every intent that loads a book by URL.
private let abbayCannotFindDialog = LocalizedStringResource(
    "siriCannotFind",
    defaultValue: "Cannot find that audiobook. It may have been removed or is not downloaded."
)

private func abbayPlayingDialog(title: String) -> LocalizedStringResource {
    LocalizedStringResource("siriPlayingTitle", defaultValue: "Playing \(title).")
}

/// "Say 'Play in Abbay'" names the Resume phrase; pt-BR names its own registered phrase.
private let abbayNothingPlayingHintDialog = LocalizedStringResource(
    "siriNothingPlayingHint",
    defaultValue: "Nothing is playing. Say 'Play in Abbay' to start."
)

// MARK: - Resume

struct ResumeAbbayIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play in Abbay"
    static let description = IntentDescription("Resumes the last audiobook you played in Abbay.")

    static let addBookDialog = LocalizedStringResource("siriAddBookFirst", defaultValue: "Add a book in Abbay first.")
    static let cannotFindDialog = abbayCannotFindDialog

    static func playingDialog(title: String) -> LocalizedStringResource {
        abbayPlayingDialog(title: title)
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        DependencyContainer.diagnostics.record("appintent ResumeAbbayIntent fired")
        // Attempt audio session activation. If it succeeds, clears the flag (so a
        // stale `true` from a previous cold-launch failure no longer sticks). If
        // it still throws, sets the flag and exits with the unavailable dialog.
        guard AudioSessionActivator.attemptActivation() else {
            return .result(dialog: IntentDialog(abbayAudioUnavailableDialog))
        }
        guard let url = DependencyContainer.lastPlayed.lastPlayedURL() else {
            return .result(dialog: IntentDialog(Self.addBookDialog))
        }
        guard var model = DependencyContainer.shared.loadAudio.execute(url: url) else {
            // Stuck-state guard: don't loop on a dead pointer.
            DependencyContainer.lastPlayed.save(url: nil)
            return .result(dialog: IntentDialog(Self.cannotFindDialog))
        }
        DependencyContainer.shared.player.play(&model)
        return .result(dialog: IntentDialog(Self.playingDialog(title: model.title)))
    }
}

// MARK: - Pause

struct PauseAbbayIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Pause Abbay"
    static let description = IntentDescription("Pauses the current audiobook in Abbay.")

    static let nothingPlayingDialog = LocalizedStringResource("siriNothingPlaying", defaultValue: "Nothing is playing.")
    static let pausedDialog = LocalizedStringResource("siriPaused", defaultValue: "Paused.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        DependencyContainer.diagnostics.record("appintent PauseAbbayIntent fired")
        // Attempt audio session activation. If it succeeds, clears the flag (so a
        // stale `true` from a previous cold-launch failure no longer sticks). If
        // it still throws, sets the flag and exits with the unavailable dialog.
        guard AudioSessionActivator.attemptActivation() else {
            return .result(dialog: IntentDialog(abbayAudioUnavailableDialog))
        }
        guard NowPlayingManager.shared.currentAudio != nil else {
            return .result(dialog: IntentDialog(Self.nothingPlayingDialog))
        }
        DependencyContainer.shared.player.pause()
        return .result(dialog: IntentDialog(Self.pausedDialog))
    }
}

// MARK: - Next chapter

struct NextChapterIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next chapter in Abbay"
    static let description = IntentDescription("Skips to the next chapter of the audiobook playing in Abbay.")

    static let nothingPlayingDialog = abbayNothingPlayingHintDialog
    static let nextChapterDialog = LocalizedStringResource("siriNextChapter", defaultValue: "Next chapter.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        DependencyContainer.diagnostics.record("appintent NextChapterIntent fired")
        // Attempt audio session activation. If it succeeds, clears the flag (so a
        // stale `true` from a previous cold-launch failure no longer sticks). If
        // it still throws, sets the flag and exits with the unavailable dialog.
        guard AudioSessionActivator.attemptActivation() else {
            return .result(dialog: IntentDialog(abbayAudioUnavailableDialog))
        }
        guard NowPlayingManager.shared.currentAudio != nil else {
            return .result(dialog: IntentDialog(Self.nothingPlayingDialog))
        }
        DependencyContainer.shared.player.skipToNextChapter()
        return .result(dialog: IntentDialog(Self.nextChapterDialog))
    }
}

// MARK: - Previous chapter

struct PreviousChapterIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous chapter in Abbay"
    static let description = IntentDescription("Skips to the previous chapter of the audiobook playing in Abbay.")

    static let nothingPlayingDialog = abbayNothingPlayingHintDialog
    static let previousChapterDialog = LocalizedStringResource("siriPreviousChapter", defaultValue: "Previous chapter.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        DependencyContainer.diagnostics.record("appintent PreviousChapterIntent fired")
        // Attempt audio session activation. If it succeeds, clears the flag (so a
        // stale `true` from a previous cold-launch failure no longer sticks). If
        // it still throws, sets the flag and exits with the unavailable dialog.
        guard AudioSessionActivator.attemptActivation() else {
            return .result(dialog: IntentDialog(abbayAudioUnavailableDialog))
        }
        guard NowPlayingManager.shared.currentAudio != nil else {
            return .result(dialog: IntentDialog(Self.nothingPlayingDialog))
        }
        DependencyContainer.shared.player.skipToPreviousChapter()
        return .result(dialog: IntentDialog(Self.previousChapterDialog))
    }
}

// MARK: - Play book by name

struct PlayBookByNameIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play audiobook in Abbay"
    static let description = IntentDescription("Plays a specific audiobook in Abbay by name.")

    @Parameter(title: "Audiobook", requestValueDialog: IntentDialog("Which audiobook?"))
    var bookName: String

    static func noMatchDialog(_ input: String) -> LocalizedStringResource {
        LocalizedStringResource("siriNoMatch", defaultValue: "No audiobook matches '\(input)'.")
    }

    static let cannotFindDialog = abbayCannotFindDialog

    static func playingDialog(title: String) -> LocalizedStringResource {
        abbayPlayingDialog(title: title)
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        DependencyContainer.diagnostics.record("appintent PlayBookByNameIntent fired")
        // Attempt audio session activation. If it succeeds, clears the flag (so a
        // stale `true` from a previous cold-launch failure no longer sticks). If
        // it still throws, sets the flag and exits with the unavailable dialog.
        guard AudioSessionActivator.attemptActivation() else {
            return .result(dialog: IntentDialog(abbayAudioUnavailableDialog))
        }
        let library = DependencyContainer.shared.loadAllAudios.execute()
        let lastPlayed = DependencyContainer.lastPlayed.lastPlayedURL()
        guard let hit = fuzzyMatch(input: bookName, audios: library, lastPlayedURL: lastPlayed),
              let url = hit.url else {
            return .result(dialog: IntentDialog(Self.noMatchDialog(bookName)))
        }
        guard var model = DependencyContainer.shared.loadAudio.execute(url: url) else {
            // Stuck-state guard: clear pointer only if the dead match is the saved one.
            if DependencyContainer.lastPlayed.lastPlayedURL() == url {
                DependencyContainer.lastPlayed.save(url: nil)
            }
            return .result(dialog: IntentDialog(Self.cannotFindDialog))
        }
        DependencyContainer.shared.player.play(&model)
        return .result(dialog: IntentDialog(Self.playingDialog(title: model.title)))
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

    static let cannotFindDialog = abbayCannotFindDialog

    static func playingDialog(title: String) -> LocalizedStringResource {
        abbayPlayingDialog(title: title)
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        DependencyContainer.diagnostics.record("appintent PlayAudiobookIntent fired")
        guard AudioSessionActivator.attemptActivation() else {
            return .result(dialog: IntentDialog(abbayAudioUnavailableDialog))
        }
        return .result(dialog: IntentDialog(abbayPlayBook(at: audiobook.url)))
    }
}

/// Loads and plays the book at `url`, for the intents that name a book (`PlayAudiobookIntent`, and
/// iOS 27's `PlayAudioDomainIntent`). Returns what to say: *"Playing <title>."*, or the
/// cannot-find dialog when the book is gone, after clearing the last-played pointer if it was that
/// book (so Resume doesn't loop on it).
@MainActor
func abbayPlayBook(at url: URL?) -> LocalizedStringResource {
    guard let url, var model = DependencyContainer.shared.loadAudio.execute(url: url) else {
        if let url, DependencyContainer.lastPlayed.lastPlayedURL() == url {
            DependencyContainer.lastPlayed.save(url: nil)
        }
        return abbayCannotFindDialog
    }
    DependencyContainer.shared.player.play(&model)
    return abbayPlayingDialog(title: model.title)
}

// MARK: - Play a specific chapter

/// "Play chapter 4 in Abbay". Acts on the book that is playing, or resumes the
/// last-played book positioned at the requested chapter when nothing is loaded.
struct PlayChapterIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play chapter"
    static let description = IntentDescription("Jumps to a chapter of the audiobook you are listening to.")

    @Parameter(title: "Chapter")
    var chapter: ChapterEntity

    static let nothingToPlayDialog = LocalizedStringResource(
        "siriNothingToPlay",
        defaultValue: "Nothing to play. Say 'Play in Abbay' to start a book."
    )

    static func noChapterDialog(_ number: Int) -> LocalizedStringResource {
        LocalizedStringResource("siriNoChapter", defaultValue: "That audiobook doesn't have a chapter \(number).")
    }

    static func playingChapterDialog(_ number: Int) -> LocalizedStringResource {
        LocalizedStringResource("siriPlayingChapter", defaultValue: "Playing chapter \(number).")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        DependencyContainer.diagnostics.record("appintent PlayChapterIntent fired")
        guard AudioSessionActivator.attemptActivation() else {
            return .result(dialog: IntentDialog(abbayAudioUnavailableDialog))
        }
        let index = chapter.id

        // Already listening: a seek is enough, and it avoids reloading the item.
        if NowPlayingManager.shared.currentAudio != nil,
           DependencyContainer.shared.player.playChapter(at: index) {
            return .result(dialog: IntentDialog(Self.playingChapterDialog(chapter.number)))
        }

        // Cold: resume the last-played book, but start it at the requested chapter.
        // Setting `currentTime` before `play` avoids racing the seek against
        // AVPlayerItem loading.
        guard let url = DependencyContainer.lastPlayed.lastPlayedURL(),
              var model = DependencyContainer.shared.loadAudio.execute(url: url) else {
            return .result(dialog: IntentDialog(Self.nothingToPlayDialog))
        }
        guard model.chapters.indices.contains(index) else {
            return .result(dialog: IntentDialog(Self.noChapterDialog(chapter.number)))
        }
        model.currentTime = model.chapters[index].startTime
        DependencyContainer.shared.player.play(&model)
        return .result(dialog: IntentDialog(Self.playingChapterDialog(chapter.number)))
    }
}

// MARK: - App Shortcuts (phrase registration)

struct AbbayAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResumeAbbayIntent(),
            phrases: [
                "\(.applicationName) play",
                "\(.applicationName) resume",
                "Play in \(.applicationName)",
                "Play on \(.applicationName)",
                "Play \(.applicationName)",
                "Resume \(.applicationName)",
                "Continue audiobook in \(.applicationName)",
                "Continue audiobook on \(.applicationName)"
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
                "Next chapter on \(.applicationName)",
                "Skip chapter in \(.applicationName)",
                "Skip chapter on \(.applicationName)"
            ],
            shortTitle: "Next chapter",
            systemImageName: "forward.fill"
        )
        AppShortcut(
            intent: PreviousChapterIntent(),
            phrases: [
                "Previous chapter in \(.applicationName)",
                "Previous chapter on \(.applicationName)"
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
            // App-name-first variants matter: Siri completes a known media title
            // from our own registered vocabulary and then ends the utterance,
            // dropping anything after it. Leading with the app name means the
            // target app is established before the title, so a truncated tail
            // costs nothing. "on" and "using" variants matter too: without them, "Play <book>
            // on Abbay" matched no Abbay phrase and Siri routed it as a generic media request
            // to the default music app.
            phrases: [
                "\(.applicationName) play \(\.$audiobook)",
                "\(.applicationName) open \(\.$audiobook)",
                "In \(.applicationName) play \(\.$audiobook)",
                "Play \(\.$audiobook) in \(.applicationName)",
                "Play \(\.$audiobook) on \(.applicationName)",
                "Play \(\.$audiobook) using \(.applicationName)",
                "Open \(\.$audiobook) in \(.applicationName)",
                "Open \(\.$audiobook) on \(.applicationName)",
                "Listen to \(\.$audiobook) in \(.applicationName)",
                "Listen to \(\.$audiobook) on \(.applicationName)"
            ],
            shortTitle: "Play audiobook",
            systemImageName: "books.vertical.fill"
        )
        AppShortcut(
            intent: PlayChapterIntent(),
            phrases: [
                "\(.applicationName) play \(\.$chapter)",
                "In \(.applicationName) play \(\.$chapter)",
                "Play \(\.$chapter) in \(.applicationName)",
                "Play \(\.$chapter) on \(.applicationName)",
                "Skip to \(\.$chapter) in \(.applicationName)",
                "Skip to \(\.$chapter) on \(.applicationName)"
            ],
            shortTitle: "Play chapter",
            systemImageName: "list.number"
        )
        AppShortcut(
            intent: PlayBookByNameIntent(),
            phrases: [
                "Play audiobook in \(.applicationName)",
                "Play audiobook on \(.applicationName)",
                "Pick audiobook in \(.applicationName)",
                "Pick audiobook on \(.applicationName)"
            ],
            shortTitle: "Play audiobook",
            systemImageName: "book.fill"
        )
    }
}
