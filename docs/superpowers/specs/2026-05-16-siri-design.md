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
| `ResumeAbbayIntent` | "Play in Abbay", "Resume Abbay", "Continue audiobook in Abbay" | Load last-played URL from `LastPlayedStore`. If nil: dialog `"Add a book in Abbay first."`. If `LoadAudioUseCase.execute(url:)` returns nil (file deleted / iCloud not downloaded): dialog `"Cannot find that audiobook. It may have been removed or is not downloaded."`. Otherwise: `player.play(&model)` and dialog `"Playing \(title)."` |
| `PauseAbbayIntent` | "Pause Abbay" | If `NowPlayingManager.shared.currentAudio == nil`: dialog `"Nothing is playing."`. Else `player.pause()` and dialog `"Paused."` |
| `NextChapterIntent` | "Next chapter in Abbay", "Skip chapter in Abbay" | Requires active playback. If `NowPlayingManager.shared.currentAudio == nil`: dialog `"Nothing is playing. Say 'Play in Abbay' to start."`. Else `player.skipToNextChapter()` and dialog `"Next chapter."` |
| `PreviousChapterIntent` | "Previous chapter in Abbay" | Same precondition as Next. Else `player.skipToPreviousChapter()` and dialog `"Previous chapter."` |
| `PlayBookByNameIntent` | "Play \\($book) in Abbay" | Fuzzy-match library by title (see rule below). No match: dialog `"No audiobook matches '\(input)'."`. Match found but file unreachable: dialog `"Cannot find that audiobook. It may have been removed or is not downloaded."`. Else `player.play(&model)` and dialog `"Playing \(title)."` |

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
- Uses Apple's `AppIntents` framework. **Deployment target bump from iOS 15 to iOS 16 is required** — update `IPHONEOS_DEPLOYMENT_TARGET` in `project.yml` from `'15.0'` to `'16.0'`.
- Each intent declares `openAppWhenRun = true`. `@MainActor` is applied **only** to `perform()` bodies that touch main-actor-isolated state (the `Player` and `NowPlayingManager` interact with `AVPlayer` / `MPNowPlayingInfoCenter`, so all current perform() bodies do qualify). No type-level `@MainActor`.
- Intents reach the live player via `DependencyContainer.shared.player` (already singleton-configured at launch). Existing `DependencyContainer.configure(with:)` permits mock injection for tests.
- Library access via existing `LoadAllAudiosUseCase` and `LoadAudioUseCase`.
- Last-played URL persisted in `UserDefaults.standard` via a small `LastPlayedStore`.

### CarPlay scope (v1)

v1 covers two CarPlay flows:

1. **In-CarPlay UI playback controls** — already supported via `MPRemoteCommandCenter` in `NowPlayingManager`. Not new in this PR.
2. **Explicit-app-name Siri** — phrases like `"... in Abbay"` work because the system launches the app (or routes to the running app); the existing `CarPlaySceneDelegate` is unaffected.

**Not covered in v1:** no-app-name Siri routing in CarPlay (`"Play my audiobook"`). That requires either `INPlayMediaIntent` (SiriKit) or `AudioPlaybackIntent` (iOS 17+ AppIntents). Both deferred to phase 2 — see Non-goals.

## Fuzzy match rule (centralized helper, unit-tested)

```
normalize(s):
  1. Replace "&" with " and "  (do this BEFORE punctuation stripping)
  2. Lowercase
  3. Remove characters in CharacterSet.punctuationCharacters ∪ CharacterSet.symbols
  4. Collapse runs of whitespace to a single space
  5. Trim leading/trailing whitespace

score(audio, input):
  let t = normalize(audio.title); let q = normalize(input)
  3 if t == q
  2 else if t.hasPrefix(q)
  1 else if t.contains(q)
  0 else

match(library, input, lastPlayedURL):
  filter library to score > 0
  sort by (score DESC, url == lastPlayedURL first, library index ASC)
  return first; nil if filtered list is empty
```

Helper lives in `AbbayIntents.swift` as a pure free function `fuzzyMatch(input:audios:lastPlayedURL:) -> AudioModel?`. Pure, no side effects, easy to unit-test.

Test vectors that must be locked in (`FuzzyMatchTests`):
- `"harry potter"` vs stored `"Harry Potter"` → score 3 (exact after normalize)
- `"harry"` vs stored `"Harry Potter and the Sorcerer's Stone"` → score 2 (prefix)
- `"sorcerer"` vs same → score 1 (contains)
- `"Harry Potter & the Philosophers Stone"` (spoken) vs stored `"Harry Potter and the Philosophers Stone"` → score 3 (`&` → `and` normalization)
- `"Don't Look Up"` (with apostrophe) vs stored `"Dont Look Up"` → score 3 (punctuation stripped both sides)
- `"book"` matching two titles, one being last-played → returns last-played one
- `"xyz"` vs library → nil
- Empty input → nil

## File changes

### New files

- `Abbay/Intents/AbbayIntents.swift`
  - All 5 `AppIntent` structs
  - `AudioEntity: AppEntity` + `AudioEntityQuery: EntityQuery, EntityStringQuery`
  - `AbbayAppShortcuts: AppShortcutsProvider`
  - `fuzzyMatch(input:audios:lastPlayedURL:)` free function (pure)

- `Abbay/Core/LastPlayedStore.swift`
  - `enum LastPlayedStore` using `UserDefaults.standard`
  - Key: `abbay.lastPlayedAudioURL`
  - `static func save(url: URL?)` / `static func lastPlayedURL() -> URL?`
  - Optional `static var defaults: UserDefaults = .standard` for test injection

### Edits

- `Abbay/Core/Player/Player.swift` — single line in `updatePlayItem`: `LastPlayedStore.save(url: url)`. `url` here is `AudioModel.url` — the book-level file URL (one URL per audiobook; chapters are timestamp metadata inside that file, not separate files).
- `Abbay/View/MediaListView/MediaListViewModel.swift` — after library load and after delete, call `AbbayAppShortcuts.updateAppShortcutParameters()` so Siri picks up entity changes
- `project.yml` — bump `IPHONEOS_DEPLOYMENT_TARGET` from `'15.0'` to `'16.0'` (required for `AppIntents`)

### Info.plist and entitlements — explicitly NOT changed in v1

- **`NSSiriUsageDescription` — NOT added.** This key is a SiriKit-era privacy declaration required when an app calls `INPreferences.requestSiriAuthorization`. Pure `AppIntents` apps do not call that API and do not surface a Siri authorization prompt. Adding the key would be unused noise and could trigger a misleading permission prompt or App Store review questions.
- **`com.apple.developer.siri` entitlement — NOT added.** This is the SiriKit / `IntentsExtension` capability. Pure `AppIntents` on iOS 16+ do not require it. Reintroduce only if/when phase 2 lands `INPlayMediaIntent` or a SiriKit-based extension.

## Cold-start contract

For v1 (in-app `AppIntent` with `openAppWhenRun = true` and the existing UIKit `AppDelegate`):

1. The system brings the app to the foreground if it is not running.
2. `application(_:didFinishLaunchingWithOptions:)` runs to completion — activates `AVAudioSession` for `.playback`, then calls `DependencyContainer.configure()`. Both are synchronous.
3. The intent body runs.

Therefore `DependencyContainer.shared.player` and an active `AVAudioSession` are both guaranteed by the time any intent body executes. No extra orchestration needed for v1.

`NowPlayingManager.shared.currentAudio` is `nil` until the user has played at least once in the current process. `NextChapterIntent` and `PreviousChapterIntent` **do not** attempt to resume + skip in the same call — that would race against asynchronous `AVPlayerItem` loading (the skip would target either no asset or stale state before `readyToPlay`). They short-circuit with a clear spoken prompt instead (see Scope table).

### Phase-2 migration notes (not implemented in v1)

These items intentionally accept brittleness now to keep v1 small. Each is a known wiring change at phase-2 time, not a rewrite:

- **`AppIntentsExtension` migration:** intents would run in a separate process where `AppDelegate.didFinishLaunching` never runs and `DependencyContainer.shared` is a fresh instance. Phase-2 task will introduce an explicit per-process bootstrap (e.g. a `BootstrapLoader` invoked from both `AppDelegate` and the extension's principal class) before touching `DependencyContainer.shared`. v1 keeps the existing `fatalError`-on-unconfigured contract from `DependencyContainer.swift`.
- **`LastPlayedStore` cross-process migration:** v1 uses `UserDefaults.standard`. Phase-2 extension cannot read that. Migration plan: switch `LastPlayedStore.defaults` to `UserDefaults(suiteName: "group.com.edyuto.abbay")` and, at first launch of the phase-2 build, copy the existing `UserDefaults.standard` value into the App Group suite under the same key. Users keep their last-played pointer.
- **`AudioPlaybackIntent` adoption:** requires iOS 17+. Once the project bumps deployment to iOS 17, conform `ResumeAbbayIntent`, `PauseAbbayIntent`, `NextChapterIntent`, `PreviousChapterIntent`, and `PlayBookByNameIntent` to `AudioPlaybackIntent` and drop `openAppWhenRun = true` on the four control intents. This unlocks lock-screen / AirPods / no-app-name CarPlay routing without foregrounding the UI.

## Tests

Live in `AbbayTests`:

- `FuzzyMatchTests` — exact / prefix / contains / no-match / punctuation strip / last-played tiebreak / case insensitivity
- `LastPlayedStoreTests` — round-trip save and read, nil round-trip, isolation via injected `UserDefaults` suite
- Intent `perform()` smoke tests using a mock `DependencyContainerProtocol` (the container already supports `configure(with:)`), asserting:
  - `ResumeAbbayIntent` plays last-played audio when present
  - `ResumeAbbayIntent` returns expected dialog when no last-played
  - `ResumeAbbayIntent` returns "cannot find" dialog when `LoadAudioUseCase` returns nil for a saved URL
  - `PauseAbbayIntent` calls `player.pause()` when `currentAudio != nil`; returns "Nothing is playing." otherwise
  - `NextChapterIntent` returns the "say 'Play in Abbay'" prompt when `currentAudio == nil`; calls `skipToNextChapter()` otherwise
  - `PreviousChapterIntent` same precondition behavior as Next
  - `PlayBookByNameIntent` picks the correct entity given fixed library + last-played, including the `&` vs `and` normalization vector

## Manual verification checklist

- Add an audiobook. Play it. Background the app. Say "Hey Siri, pause Abbay". Confirm playback paused via lock screen Now Playing.
- "Hey Siri, next chapter in Abbay" — seeks forward by chapter.
- "Hey Siri, previous chapter in Abbay" — uses the >15s rule already in `Player.skipToPreviousChapter`.
- Kill app. "Hey Siri, play in Abbay" — app launches, resumes last book at saved time.
- "Hey Siri, play [partial title] in Abbay" — plays the fuzzy match.
- Empty library cold start. "Hey Siri, play in Abbay" — spoken dialog: "Add a book in Abbay first."
- CarPlay session: connect device, launch Abbay on CarPlay, repeat the four playback-control phrases above.

## Risks

- Intent body holds the main actor (where applied) while `player.play()` mutates state. Should be fast; if it becomes slow, push heavy work off-main and short-circuit the dialog.
- `LoadAudioUseCase` returns nil if the underlying file URL is no longer reachable (book deleted, iCloud not downloaded). Dialog strings for this case are pinned in the Scope table.
- `currentAudio` nil edge case for skip intents — handled by short-circuiting with a spoken prompt, not by attempting an in-flight resume + skip (see Cold-start contract).
- Deployment target bump from iOS 15 to iOS 16 drops support for iOS 15 devices. Accepted cost for AppIntents availability.

## Out of scope, but candidate for phase 2

- `AudioPlaybackIntent` adoption (iOS 17+ requirement) — unlocks lock-screen / AirPods / no-app-name CarPlay routing without foregrounding the UI.
- `INPlayMediaIntent` extension to enable "Hey Siri, play [book name]" without saying "in Abbay".
- `AppIntentsExtension` target (background intent execution) with App Group + `LastPlayedStore` migration plan above.
- Play specific chapter by number or by name.
- Spoken language localization.
