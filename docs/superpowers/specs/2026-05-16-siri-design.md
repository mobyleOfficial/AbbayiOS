# Siri Integration Design

**Date:** 2026-05-16
**Branch:** `feat/siri`
**Status:** Approved, pending implementation plan

## Goal

Add voice control over audiobook playback in Abbay via Siri. Ship the minimum that works reliably; defer everything else.

## Scope (v1)

Five intents:

| Intent | Phrases | Behavior |
| --- | --- | --- |
| `ResumeAbbayIntent` | "Play in Abbay", "Resume Abbay", "Continue audiobook in Abbay" | Load last-played URL from `LastPlayedStore`, fetch model via `LoadAudioUseCase`, call `player.play(&model)`. If no last-played: spoken dialog `"Add a book in Abbay first."` |
| `PauseAbbayIntent` | "Pause Abbay" | If `NowPlayingManager.shared.currentAudio == nil`: dialog `"Nothing is playing."`. Else `player.pause()` and dialog `"Paused."` |
| `NextChapterIntent` | "Next chapter in Abbay", "Skip chapter in Abbay" | If `NowPlayingManager.shared.currentAudio == nil`, first do the resume flow. Then `player.skipToNextChapter()`. |
| `PreviousChapterIntent` | "Previous chapter in Abbay" | Same fallback. Then `player.skipToPreviousChapter()`. |
| `PlayBookByNameIntent` | "Play \\($book) in Abbay" | Fuzzy-match library by title, play winning model. |

## Non-goals (deferred to phase 2)

- Play chapter by number or by name (user marked problematic, defer until base works)
- `INPlayMediaIntent` extension (no-app-name routing in CarPlay / general Siri)
- `AppIntentsExtension` target (background intent execution)
- App Group / shared Core Data store
- `AbbayKit` framework extraction
- Localization of Siri dialog strings (English only for v1)
- `INInteraction` donations (AppShortcuts handles discovery)
- Disambiguation flow when multiple titles match
- Now-playing artwork donation to Siri

## Architecture

- All intent code lives in the existing `Abbay` application target.
- No new framework, no extension target, no App Group.
- Uses Apple's `AppIntents` framework (iOS 16+).
- Every intent: `@MainActor`, `openAppWhenRun = true`.
- Intents reach the live player via `DependencyContainer.shared.player` (already singleton-configured at launch).
- Library access via existing `LoadAllAudiosUseCase` and `LoadAudioUseCase`.
- Last-played URL persisted in `UserDefaults.standard` via a small `LastPlayedStore`.
- CarPlay: untouched. `MPRemoteCommandCenter` already covers in-car play/pause/skip from `NowPlayingManager`. Siri-on-CarPlay works because app foregrounds into existing `CarPlaySceneDelegate`.

## Fuzzy match rule (centralized helper, unit-tested)

```
1. normalize(s) = lowercased, trimmed, whitespace collapsed, punctuation stripped
2. For each audio in library compute score:
   3 if normalize(title) == normalize(input)
   2 else if normalize(title).hasPrefix(normalize(input))
   1 else if normalize(title).contains(normalize(input))
   0 else
3. Filter to score > 0.
4. Sort by score desc; tie-break by url == LastPlayedStore.url first, else preserve library order.
5. Take first. If list empty: spoken dialog "No audiobook matches '\(input)'."
```

Helper lives in `AbbayIntents.swift` (or split if it grows). Pure function, easy to unit-test.

## File changes

### New files

- `Abbay/Intents/AbbayIntents.swift`
  - All 5 `AppIntent` structs
  - `AudioEntity: AppEntity` + `AudioEntityQuery: EntityQuery, EntityStringQuery`
  - `AbbayAppShortcuts: AppShortcutsProvider`
  - `FuzzyMatcher` helper (pure function)

- `Abbay/Core/LastPlayedStore.swift`
  - `enum LastPlayedStore` using `UserDefaults.standard`
  - Key: `abbay.lastPlayedAudioURL`
  - `static func save(url: URL?)` / `static func lastPlayedURL() -> URL?`
  - Optional `static var defaults: UserDefaults = .standard` for test injection

### Edits

- `Abbay/Core/Player/Player.swift` — single line in `updatePlayItem`: `LastPlayedStore.save(url: url)`
- `Abbay/View/MediaListView/MediaListViewModel.swift` — after library load and after delete, call `AbbayAppShortcuts.updateAppShortcutParameters()` so Siri picks up entity changes
- `Abbay/Resources/Info.plist` — add `NSSiriUsageDescription` string
- `Abbay/Resources/Abbay.entitlements` — add `com.apple.developer.siri` set to `true`
- `project.yml` — no change required

## Cold-start contract

`AppIntent.perform()` runs after `application(_:didFinishLaunchingWithOptions:)`. The current `AppDelegate.didFinishLaunching`:

1. Activates `AVAudioSession` for `.playback`
2. Calls `DependencyContainer.configure()`

Both are synchronous and complete before any intent body runs. No extra orchestration needed.

`NowPlayingManager.shared.currentAudio` is `nil` until the user has played at least once in the current process. `NextChapterIntent` and `PreviousChapterIntent` must therefore fall back to the resume-last-played flow before calling skip.

## Tests

Live in `AbbayTests`:

- `FuzzyMatchTests` — exact / prefix / contains / no-match / punctuation strip / last-played tiebreak / case insensitivity
- `LastPlayedStoreTests` — round-trip save and read, nil round-trip, isolation via injected `UserDefaults` suite
- Intent `perform()` smoke tests using a mock `DependencyContainerProtocol` (the container already supports `configure(with:)`), asserting:
  - `ResumeAbbayIntent` plays last-played audio when present
  - `ResumeAbbayIntent` returns expected dialog when no last-played
  - `PauseAbbayIntent` calls `player.pause()`
  - `NextChapterIntent` and `PreviousChapterIntent` resume-then-skip when no current audio
  - `PlayBookByNameIntent` picks the correct entity given fixed library + last-played

## Manual verification checklist

- Add an audiobook. Play it. Background the app. Say "Hey Siri, pause Abbay". Confirm playback paused via lock screen Now Playing.
- "Hey Siri, next chapter in Abbay" — seeks forward by chapter.
- "Hey Siri, previous chapter in Abbay" — uses the >15s rule already in `Player.skipToPreviousChapter`.
- Kill app. "Hey Siri, play in Abbay" — app launches, resumes last book at saved time.
- "Hey Siri, play [partial title] in Abbay" — plays the fuzzy match.
- Empty library cold start. "Hey Siri, play in Abbay" — spoken dialog: "Add a book in Abbay first."
- CarPlay session: connect device, launch Abbay on CarPlay, repeat the four playback-control phrases above.

## Risks

- Intent body holds the main actor while `player.play()` mutates state. Should be fast; if it becomes slow, push heavy work off-main and short-circuit the dialog.
- `LoadAudioUseCase` returns nil if the underlying file URL is no longer reachable (book deleted, iCloud not downloaded). Each intent must guard against nil and speak a clear failure dialog rather than silently fail.
- `currentAudio` nil edge case for skip intents — covered by resume-first fallback above.

## Out of scope, but candidate for phase 2

- `INPlayMediaIntent` extension to enable "Hey Siri, play [book name]" without saying "in Abbay" — only worth adding after phase 1 has real usage.
- Play specific chapter by number or by name.
- Spoken language localization.
