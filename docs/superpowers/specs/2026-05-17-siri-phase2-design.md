# Siri Integration Phase 2 — Design

**Date:** 2026-05-17
**Branch:** `feat/siri-phase2` (off `feat/siri-impl`)
**Status:** Approved, pending implementation plan
**Companions:** phase 1 spec `2026-05-16-siri-design.md`, phase 1 plan `2026-05-16-siri.md`, phase 1 limitations `2026-05-17-phase-1-limitations.md`, research `2026-05-17-sirikit-media-providers.md`

## Goal

Resolve the four phase-1 limitations rooted in the SiriKit Media domain (cold-start "play" mis-routing, two-step `PlayBookByName` interaction, AppShortcut entity-parameter restriction, no multi-match disambiguation) and the cold-launch-during-call crash. Ship the `INPlayMediaIntent` extension every shipping iOS media app uses for these flows, plus the App Group + graceful-launch infrastructure that unblocks it.

Headline UX target: `"Hey Siri, play Harry Potter and the Goblet of Fire on Abbay"` cold-starts the app and plays that book — single utterance, no second prompt.

## Scope (phase 2)

Three coupled changes that ship in one PR:

1. **`INPlayMediaIntent` extension target `AbbayIntents`.** New app-extension target conforming to `INPlayMediaIntentHandling`. Wins Siri's media-router priority for the "play" verb cold-start; carries `INMediaSearch.mediaName` as an arbitrary spoken string; supports custom no-match dialog with input echo; supports multi-match disambiguation.
2. **App Group `group.com.edyuto.abbay` enabled on both targets.** Canonical cross-process store via `UserDefaults(suiteName:)`. Hosts the migrated `LastPlayedStore`, the new library snapshot, and the new launch-state flag.
3. **`AppDelegate.fatalError` → graceful launch-state flag.** Replace the existing `try AVAudioSession.sharedInstance().setActive(true)` / `fatalError` pattern with a flag write to the App Group. All five existing AppIntents AND the new extension read the flag; when set, they speak `"Audio temporarily unavailable. Try again in a moment."` instead of crashing.

Plus two UX polish items that the extension enables:

4. **Live disambiguation.** When `fuzzyMatch` returns multiple matches in the same score band, the extension returns `INPlayMediaMediaItemResolutionResult.disambiguation(with:)` instead of `.success(with:)`. Siri prompts the user to pick.
5. **`INPlayMediaIntent` donations.** After every successful play start in the main app — whether triggered by the new extension, an existing AppIntent, or a manual user tap — donate `INPlayMediaIntent` via `INInteraction(intent:response:).donate()`. Feeds Siri's preferred-media-app learning so `"Hey Siri, play Harry Potter"` (no `"on Abbay"`) gradually routes to Abbay for users who play in Abbay regularly.

### Phase-2 fix coverage (against phase 1 limitations doc)

| # | Phase 1 limitation | Phase 2 fix |
|---|---|---|
| 1 | Cold-start `"play"` → wrong app | `INPlayMediaIntent` extension wins media-router priority |
| 2 | Cold-launch-during-call crash | `LaunchStateFlag` replaces `fatalError`; intent dialogs read flag |
| 3 | `PlayBookByNameIntent` is two-step | `INMediaSearch.mediaName` is arbitrary String; one-shot phrase works |
| 5 | AppShortcut entity-parameter restriction | Bypassed — extension is not AppIntents |
| 9 | No multi-match disambiguation | `INPlayMediaMediaItemResolutionResult.disambiguation(with:)` |

Limitations #4 (security-scoped URL round-trip), #6 (iOS 17 minimum), #7 (CarPlay scene routing), #8 (English-only dialogs), #10 (AppShortcuts indexing requires one launch), #11 (`IntentDialog` not introspectable), #12 (`"Abbay"` STT phonetic ambiguity) are unchanged from phase 1. #4's `bookmarkData` round-trip is partially addressed here: the snapshot persists `bookmarkData`, so the extension's identifier round-trip uses bookmarks. The existing AppIntents path still uses `absoluteString` until a future phase migrates the in-app save site.

## Non-goals (deferred to phase 3 / later)

- **Self-containment of the extension** (Core Data in extension, or `AbbayKit` framework extraction). Phase 2 uses a JSON snapshot in App Group `UserDefaults` instead. Phase 3 trigger: a concrete need for in-extension playback, deeper shared state, or test the snapshot path proved insufficient.
- **AppIntents `AssistantSchemas`** (`playMedia` / `playAudiobook`). Captured as a GitHub issue on AbbayiOS for a future phase. Apple Intelligence-eligible devices only; additive on top of the current AppIntents stack.
- **`AppIntentsExtension` target** for the phase-1 AppIntents. Still useful for non-Siri AppIntents background execution, but not required by `INPlayMediaIntent` (which has its own extension already).
- **Localization of all Siri dialog strings.** Both phase-1 dialogs and the new phase-2 dialogs (`"Audio temporarily unavailable"`, `"No audiobook matches '<input>'"`, etc.) stay English. Future migration swaps `static let` constants to `LocalizedStringResource`; phase-2 spec is structured so this swap is additive.
- **Security-scoped URL `bookmarkData` round-trip in the existing AppIntents** path (`LastPlayedStore.lastPlayedURL`). Independent fix; not blocking. Phase 2's snapshot carries `bookmarkData` so the extension flow is unaffected.
- **CarPlay-specific scene routing hooks.** Added only if phase-2 on-device CarPlay observation reveals unwanted iPhone foregrounding.
- **`"Abbay"` STT phonetic ambiguity remedy** (e.g. `CFBundleDisplayName` rename). Needs marketing call; out of scope.

## Architecture

### Target topology

```
Abbay.xcodeproj
├── Abbay (app)
│   ├── existing code
│   ├── Core/AppGroup.swift                NEW
│   ├── Core/LibrarySnapshotWriter.swift   NEW
│   ├── Core/LaunchStateFlag.swift         NEW
│   ├── Core/LastPlayedStore.swift         EDIT (migrate to App Group)
│   ├── Core/Player/Player.swift           EDIT (donation hook)
│   ├── Intents/AbbayIntents.swift         EDIT (LaunchStateFlag reads in perform())
│   ├── AppDelegate.swift                  EDIT (replace fatalError, add handle())
│   └── View/MediaListView/MediaListViewModel.swift  EDIT (snapshot writes)
└── AbbayIntents (app-extension)           NEW TARGET
    ├── IntentHandler.swift
    ├── PlayMediaIntentHandler.swift
    ├── LibrarySnapshotReader.swift
    ├── FuzzyMatch.swift                   (pure helper, mirrors host app)
    ├── PlayMediaIntent.intentdefinition   (custom no-match Response with input echo)
    ├── Info.plist
    └── AbbayIntents.entitlements          (App Group)
```

### Cross-process state (App Group `group.com.edyuto.abbay`)

Single `UserDefaults(suiteName:)` keyed namespace. Three values:

| Key | Type | Writer | Reader |
|---|---|---|---|
| `abbay.lastPlayedAudioURL` | String? | main app (`Player.updatePlayItem`) | main app, extension |
| `abbay.librarySnapshot.v1` | Data (JSON) | main app (`LibrarySnapshotWriter` on every library load + delete + import) | extension (`LibrarySnapshotReader`) |
| `abbay.audioSessionUnavailable` | Bool | main app (`AppDelegate.didFinishLaunching` catch branch) | main app (existing AppIntents), extension (resolveMediaItems) |

Snapshot JSON shape (versioned, future-proof):

```json
{
  "version": 1,
  "updatedAt": "2026-05-17T12:34:56Z",
  "audios": [
    {
      "title": "Harry Potter and the Goblet of Fire",
      "urlString": "file:///...",
      "bookmarkData": "<base64>"
    }
  ]
}
```

The snapshot is read-only from the extension. Main app is sole writer. Writes are atomic at the UserDefaults level; no locking needed.

### Capability + entitlement deltas

**Main app target:**
- ADD App Group entitlement listing `group.com.edyuto.abbay`
- ADD `com.apple.developer.siri` entitlement
- ADD `NSSiriUsageDescription` to `Info.plist`: `"Abbay uses Siri to play your audiobooks and control playback when you say things like 'Play Harry Potter on Abbay' or 'Pause Abbay'."`

**Extension target (`AbbayIntents`):**
- App Group entitlement (same group)
- `Info.plist`: `NSExtension.NSExtensionAttributes.IntentsSupported = ["INPlayMediaIntent"]`, principal class `AbbayIntents.IntentHandler`, type `INExtension`
- No background-modes; the extension does not play audio itself

**xcodegen `project.yml`:**
- New `targets.AbbayIntents` block with `type: app-extension`, `platform: iOS`, embedded into main app via `dependencies`
- Both targets list the App Group + Siri entitlements
- `IPHONEOS_DEPLOYMENT_TARGET` stays at `17.0` from phase 1

### Phase-1 AppIntents coexistence

All five phase-1 AppIntents (`ResumeAbbayIntent`, `PauseAbbayIntent`, `NextChapterIntent`, `PreviousChapterIntent`, `PlayBookByNameIntent`) ship unchanged in shape. Edits:

- Top of each `perform()` reads `LaunchStateFlag.isUnavailable()`. If true, returns `.result(dialog: IntentDialog(Self.audioUnavailableDialog))` immediately. This is the only behavior change to phase-1 AppIntents.
- They keep handling Shortcuts, widgets, AppShortcuts phrases for non-"play" verbs (`"continue audiobook in Abbay"`, `"next chapter in Abbay"`, etc.) and the warm-state `"play in Abbay"` case.
- `PlayBookByNameIntent` is NOT retired. With `INPlayMediaIntent` live, users naturally say `"play <book> on Abbay"` and hit the extension; `PlayBookByNameIntent` remains the Shortcuts-app path (where users type a book name into the Shortcuts UI).

## Data flow

### Cold-start `"Hey Siri, play Harry Potter and the Goblet of Fire on Abbay"`

1. Siri parses utterance → media-domain router. Sees Abbay registered as `INPlayMediaIntent` provider → loads `AbbayIntents` extension.
2. Extension's `IntentHandler.handler(for: intent: INPlayMediaIntent)` returns `PlayMediaIntentHandler()`.
3. Siri calls `PlayMediaIntentHandler.resolveMediaItems(for: intent, with: completion)`.
4. Handler:
   - `LaunchStateFlag.isUnavailable()` first. If true → `completion([.unsupported(forReason: .unsupportedMediaType)])`, custom Response says `"Audio temporarily unavailable. Try again in a moment."`. STOP.
   - `LibrarySnapshotReader.read()` → `[LibraryEntry]`.
   - `fuzzyMatch(input: intent.mediaSearch?.mediaName ?? "", audios: entries, lastPlayedURL: lastPlayedURL)`:
     - 0 matches → `completion([.unsupported(forReason: .unsupportedMediaType)])`, custom Response says `"No audiobook matches '<input>'."` with input echoed via Response parameter.
     - 1 match → `completion([.success(with: INMediaItem(identifier: urlString, title: title, type: .audioBook, artwork: nil))])`.
     - 2+ matches in same score band → `completion([.disambiguation(with: matches.map(toINMediaItem))])`. Siri prompts `"Did you mean A, B, or C?"`. User picks. Siri re-invokes `resolveMediaItems` with the chosen item; handler returns `.success(with:)`.
5. Siri calls `handle(intent:completion:)`. Handler:
   - `completion(INPlayMediaIntentResponse(code: .handleInApp, userActivity: nil))` — per Apple docs, audio playback uses `.handleInApp` (NOT `.continueInApp`); the system background-launches the host app and forwards the intent.
6. iOS background-launches Abbay. `AppDelegate.application(_:didFinishLaunchingWithOptions:)` runs:
   - Existing `DependencyContainer.configure()` (synchronous, non-throwing).
   - Existing `try AVAudioSession.sharedInstance().setActive(true)`. On throw: `LaunchStateFlag.markUnavailable()` then RETURN — NO `fatalError`.
7. iOS calls `UIApplicationDelegate.application(_: app, handle: intent: INPlayMediaIntent, completionHandler:)` on the main app.
8. `AppDelegate.handle(intent:completionHandler:)`:
   - `LaunchStateFlag.isUnavailable()` → `completionHandler(INPlayMediaIntentResponse(code: .failure, userActivity: nil))`. Done.
   - Else: `intent.mediaItems?.first?.identifier` → resolve to `URL` (prefer `bookmarkData` if present in snapshot for that URL, else `URL(string: identifier)`).
   - Load `AudioModel` via existing `LoadAudioUseCase.execute(url:)`. Nil → `completionHandler(INPlayMediaIntentResponse(code: .failure))`; if the URL equals `LastPlayedStore.lastPlayedURL()`, clear it first.
   - `DependencyContainer.shared.player.play(&model)`.
   - `LastPlayedStore.save(url: model.url)`.
   - `INInteraction(intent: intent, response: INPlayMediaIntentResponse(code: .success, userActivity: nil)).donate()`.
   - `completionHandler(INPlayMediaIntentResponse(code: .success))`.

### Warm-state `"Hey Siri, play X on Abbay"` (app already running)

Same path. iOS still routes through the extension's `resolveMediaItems`, then through main app's `handle`. Main app process is already alive; `didFinishLaunching` does not re-run. `LaunchStateFlag` likely already cleared by an earlier playback cycle (see "Flag lifecycle").

### Manual play tap

User taps a book in the app. `Player.play(&model)` runs. After playback starts, the same donation hook fires: `INInteraction(intent: synthesizedINPlayMediaIntent, response: .success).donate()`. The synthesized intent carries `mediaItems: [INMediaItem(identifier: model.url.absoluteString, title: model.title, type: .audioBook)]` and `mediaSearch: INMediaSearch(mediaType: .audioBook, mediaName: model.title)`. This donation is what enables long-term `"Hey Siri, play Harry Potter"` (no `"on Abbay"`) routing to Abbay.

### Existing AppIntent (`ResumeAbbayIntent` etc.)

Top of `perform()` reads `LaunchStateFlag.isUnavailable()`. True → return `"Audio temporarily unavailable..."` dialog. False → existing phase-1 behavior. On success, `Player.play` runs through the same donation hook as manual taps.

### `LaunchStateFlag` lifecycle

- Set: `AppDelegate.didFinishLaunching` catch branch on `setActive` throw.
- Cleared: at the start of every successful `Player.play(&model)` (i.e., once playback actually starts, the audio session is by definition available). Implemented at `Player.swift`'s play site, AFTER `AVPlayer.play()` has been issued and no throw has surfaced. Atomic per playback transition.
- Read by: extension `resolveMediaItems`, extension wouldn't have set it (extension can't activate audio sessions in its own process), main app `handle`, all phase-1 AppIntent `perform()` methods.
- Expected lifetime: cleared on the next successful play. A stale `true` value persists only if the user kills the app while the flag is set AND never plays anything before next Siri invocation — acceptable; user gets the graceful dialog instead of a crash.

## Components — file-by-file

### Extension target `AbbayIntents/`

**`IntentHandler.swift`** — `~15 lines`:
```swift
import Intents
final class IntentHandler: INExtension {
    override func handler(for intent: INIntent) -> Any {
        guard intent is INPlayMediaIntent else { return self }
        return PlayMediaIntentHandler()
    }
}
```

**`PlayMediaIntentHandler.swift`** — `~80 lines`:
```swift
final class PlayMediaIntentHandler: NSObject, INPlayMediaIntentHandling {
    func resolveMediaItems(for intent: INPlayMediaIntent,
                           with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void)
    func handle(intent: INPlayMediaIntent,
                completion: @escaping (INPlayMediaIntentResponse) -> Void)
}
```

`resolveMediaItems` reads `LaunchStateFlag` first, then `LibrarySnapshotReader`, runs `fuzzyMatch`, returns the appropriate `INPlayMediaMediaItemResolutionResult` array per the table in §Data flow §Cold-start step 4. `handle` always returns `.handleInApp` — the extension never plays audio itself.

**`LibrarySnapshotReader.swift`** — `~40 lines`. Decodes `LibrarySnapshot` JSON from App Group `UserDefaults`. Exposes `static func read() -> [LibraryEntry]` returning empty array if missing/malformed.

**`FuzzyMatch.swift`** — duplicates the existing pure helper from `Abbay/Intents/AbbayIntents.swift`. Same normalization rules: `&`→`and`, lowercase, strip punctuation, collapse whitespace, trim. Same scoring: 3 exact, 2 prefix, 1 contains, 0 none. Same tiebreak: last-played first, then library index ascending. **One behavior change for phase 2:** in `match`, instead of returning the single top result, return all entries whose score equals the top score — caller decides single vs disambiguation. Existing in-app `fuzzyMatch` keeps its single-result signature for the phase-1 `PlayBookByNameIntent` flow; the extension uses the multi-result variant. Both share normalization + scoring code paths but split at the final reduction step.

**`PlayMediaIntent.intentdefinition`** — defines a custom Response with a `Failure (No Match)` template that interpolates the spoken `mediaName` into `"No audiobook matches '<input>'."`. Defining the Response in an `.intentdefinition` is the only way to get a custom no-match dialog with input echo for the legacy SiriKit Media domain ([source: phase 1 research](../research/2026-05-17-sirikit-media-providers.md#why-audioplaybackintent--appentity-cannot-match-the-ux)).

### Main-app new files

**`Abbay/Core/AppGroup.swift`** — `~20 lines`:
```swift
enum AppGroup {
    static let suiteName: String = "group.com.edyuto.abbay"
    static let defaults: UserDefaults = {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("App Group \(suiteName) not configured — check entitlements")
        }
        return defaults
    }()
}
```

The `fatalError` here is intentional and is fundamentally different from the one being removed from `AppDelegate`: this fires only if the entitlement is misconfigured at build time, which would surface immediately in development. The removed `fatalError` fires on a transient runtime condition (audio session contention) that production users hit on every cold launch during a phone call.

**`Abbay/Core/LibrarySnapshotWriter.swift`** — `~50 lines`. Encodes `[AudioModel]` to `LibrarySnapshot` JSON and writes to `AppGroup.defaults`. Called from `MediaListViewModel` after library load + delete + import. Includes `bookmarkData` when the URL is security-scoped (via `url.bookmarkData(options: .minimalBookmark)`); falls back to nil otherwise.

**`Abbay/Core/LaunchStateFlag.swift`** — `~25 lines`:
```swift
enum LaunchStateFlag {
    static func markUnavailable()
    static func clear()
    static func isUnavailable() -> Bool
}
```
All operations route through `AppGroup.defaults` keyed at `abbay.audioSessionUnavailable`.

### Main-app edits

**`Abbay/Core/LastPlayedStore.swift`** — switch `defaults` to `AppGroup.defaults`. Add migration helper called on first read after upgrade:

```
On read:
  if AppGroup.defaults has no value AND UserDefaults.standard has → return .standard value (no seed)
  else return AppGroup.defaults value (which may be nil)
On write (main app only):
  if AppGroup.defaults has no value AND UserDefaults.standard has → copy .standard into AppGroup (seed)
  ALWAYS write new value to AppGroup.defaults
```

Already pinned in phase-1 spec's "Phase-2 migration notes" section. Behavior copied verbatim here.

**`Abbay/Core/Player/Player.swift`** — after the existing `LastPlayedStore.save(url:)` call inside `updatePlayItem`, add:
1. `LaunchStateFlag.clear()` — audio session is by definition available now.
2. Donate `INPlayMediaIntent`:
   ```swift
   let mediaItem = INMediaItem(identifier: model.url.absoluteString,
                               title: model.title,
                               type: .audioBook, artwork: nil)
   let intent = INPlayMediaIntent(mediaItems: [mediaItem], mediaContainer: nil,
                                  playShuffled: nil, playbackRepeatMode: .none,
                                  resumePlayback: nil, playbackQueueLocation: .now,
                                  playbackSpeed: nil, mediaSearch:
                                    INMediaSearch(mediaType: .audioBook,
                                                  sortOrder: .unknown,
                                                  mediaName: model.title,
                                                  artistName: nil, albumName: nil,
                                                  genreNames: nil, moodNames: nil,
                                                  releaseDate: nil, reference: .none,
                                                  mediaIdentifier: nil))
   let response = INPlayMediaIntentResponse(code: .success, userActivity: nil)
   INInteraction(intent: intent, response: response).donate(completion: nil)
   ```

**`Abbay/AppDelegate.swift`**:
- Replace `fatalError` in the existing `setActive` catch branch with `LaunchStateFlag.markUnavailable()`. Do not re-raise.
- Implement `func application(_ app: UIApplication, handle intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void)` per §Data flow §Cold-start step 8.

**`Abbay/Intents/AbbayIntents.swift`** — top of each `perform()` in all five phase-1 intents:
```swift
guard !LaunchStateFlag.isUnavailable() else {
    return .result(dialog: IntentDialog(Self.audioUnavailableDialog))
}
```
With `static let audioUnavailableDialog = "Audio temporarily unavailable. Try again in a moment."` added once (e.g., on `ResumeAbbayIntent` or a shared `IntentDialogs` namespace).

**`Abbay/View/MediaListView/MediaListViewModel.swift`** — after library load and after delete, in addition to the existing `AbbayAppShortcuts.updateAppShortcutParameters()` call, also call `LibrarySnapshotWriter.write(audios: audios)`.

**`project.yml`** — add the `AbbayIntents` target, App Group entitlement on both targets, Siri entitlement + `NSSiriUsageDescription` on main app.

## Tests

### New target `AbbayIntentsTests`

Lives in `AbbayIntentsTests/`, runs in the extension's build scheme. All tests use a temporary `UserDefaults(suiteName:)` injected via the `LibrarySnapshotReader`/`LaunchStateFlag` test seams.

- `PlayMediaIntentHandlerTests.resolveMediaItems_singleMatch_returnsSuccess`
- `PlayMediaIntentHandlerTests.resolveMediaItems_multiMatch_returnsDisambiguation`
- `PlayMediaIntentHandlerTests.resolveMediaItems_noMatch_returnsUnsupportedWithNoMatchDialog`
- `PlayMediaIntentHandlerTests.resolveMediaItems_emptyLibrary_returnsUnsupportedWithEmptyLibraryDialog`
- `PlayMediaIntentHandlerTests.resolveMediaItems_audioSessionUnavailableFlag_returnsUnsupportedWithUnavailableDialog`
- `PlayMediaIntentHandlerTests.handle_alwaysReturnsHandleInApp`
- `ExtensionFuzzyMatchTests` — exact / prefix / contains / no-match / punctuation strip / `&`→`and` normalization / last-played tiebreak / multi-match (same score) — same vectors as phase-1's `FuzzyMatchTests`, locked to the extension copy of the helper.
- `LibrarySnapshotReaderTests.read_validJSON_returnsEntries`
- `LibrarySnapshotReaderTests.read_missingValue_returnsEmpty`
- `LibrarySnapshotReaderTests.read_malformedJSON_returnsEmpty`

### Extending `AbbayTests` (main app)

- `AppDelegateTests.audioSessionThrow_setsFlag_doesNotCrash` — replaces phase 1's documented crash test; verifies the flag is set and `didFinishLaunching` returns normally.
- `AppDelegateTests.handlePlayMediaIntent_callsPlayer_donates` — feeds a mock `INPlayMediaIntent`, asserts `Player.play` is called with the resolved model AND `INInteraction.donate` is invoked.
- `AppDelegateTests.handlePlayMediaIntent_audioUnavailable_returnsFailure` — flag set → completion called with failure code, `Player.play` NOT called.
- `LibrarySnapshotWriterTests.write_decodableByExtensionReader_roundTrip` — locks the JSON shape contract; the writer writes, the reader reads back identical entries (run from the main-app test target; reader code shared via a thin source-file linkage so the test compiles).
- `LastPlayedStoreTests.migration_standardToAppGroup_seedThenWrite_zeroLoss` — verifies the seed-then-write ordering preserves a pre-existing `.standard` value when the suite is empty AND does not clobber a fresh suite write.
- Existing `IntentTests` extended: each phase-1 intent's `perform()` test gets a sibling case asserting the `LaunchStateFlag.isUnavailable() == true` branch returns the unavailable dialog and does NOT call `Player`.
- Existing `IntentTests` extended: assertion that `Player.play` (or the donation hook called by it) calls `INInteraction.donate` on success — via a mock `IntentDonor` protocol injected through `DependencyContainerProtocol` (avoids hitting the real Intents framework in tests).

## Manual verification checklist

Plan task `Manual on-device verification` will spell these out; capturing the headline cases here:

- **Headline:** Kill Abbay. `"Hey Siri, play Harry Potter and the Goblet of Fire on Abbay"`. Expected: app background-launches, starts that book. ✅ No longer routes to YouTube Music.
- **Disambiguation:** Library has two Harry Potter books. Kill Abbay. `"Hey Siri, play Harry Potter on Abbay"`. Expected: Siri prompts `"Did you mean Sorcerer's Stone or Chamber of Secrets?"` → user picks → plays.
- **Graceful launch:** Kill Abbay. Start an active phone call. `"Hey Siri, play in Abbay"`. Expected: spoken `"Audio temporarily unavailable. Try again in a moment."`. NO crash. Verify via Console.app that no `AVAudioSession` `fatalError` is logged.
- **Donation learning:** Fresh device, install Abbay phase 2. Play a book manually 3+ times across separate sessions. Wait. `"Hey Siri, play Harry Potter"` (no `"on Abbay"`). Expected behavior: after enough donations, Siri starts routing to Abbay. Acceptable: this may take time and is system-managed.
- **No regression:** Phase-1 phrases (`"continue audiobook in Abbay"`, `"pause Abbay"`, `"next chapter in Abbay"`, `"previous chapter in Abbay"`) still work cold-start.
- **Migration:** Upgrade install. Existing user with `LastPlayedStore` in `.standard`. First Siri invocation reads correct last-played; subsequent main-app play writes to App Group; extension reads same value.
- **CarPlay:** Connect device to CarPlay. Repeat headline and pause/next chapter phrases. Confirm playback in CarPlay UI; note whether iPhone foregrounds (acceptable either way for phase 2; deferred CarPlay hook if unwanted foregrounding).

## Risks

- **`INPlayMediaIntent` mediaSearch reliability.** Apple Developer Forums thread [FB14872048](https://developer.apple.com/forums/thread/762196) (Aug 2024) reports occasional `mediaSearch.mediaName` truncation on long titles. Mitigation: our titles are short relative to song titles; phase-2 includes a manual checklist case verifying a long book title (`"Harry Potter and the Goblet of Fire"`) round-trips correctly. Escalate to a follow-up issue if hit.
- **Donation rate vs Siri's learning model.** Apple does not publish the threshold for `"play <X>"` (no app name) to route to a third-party media app. WWDC21 session 10231 documents donation cadence but not the routing model. Phase-2 donates on every successful play start (extension + AppIntents + manual taps); this matches Spotify-class apps. Risk: if Apple changes the model in a future iOS update, the no-app-name routing degrades silently. Mitigation: manual checklist tracks behavior; non-blocking for phase 2 since the "on Abbay" case is the headline.
- **App Group migration on existing installs.** The seed-then-write ordering covers the standard upgrade path. Edge case: user kills the app between the upgrade and first playback, then triggers Siri before re-launching. Extension reads from the App Group — which is empty — and `LastPlayedStore.lastPlayedURL()` returns nil. Handler still routes via `mediaSearch.mediaName` correctly; user sees a `"No audiobook matches..."` only if they say `"play in Abbay"` (no specific book) before re-launching. Acceptable: documented in the manual checklist; not a regression vs phase 1.
- **JSON snapshot freshness.** Snapshot is written on library load + delete + import. Edge case: user imports a book, kills app before the write completes, triggers Siri. Extension reads stale snapshot, no match for the just-imported book. Mitigation: snapshot writes are synchronous `UserDefaults.set` calls (atomic at the system level); window is sub-millisecond. Acceptable.
- **`bookmarkData` round-trip across process death** (limitation #4 in phase 1). Phase 2's snapshot persists `bookmarkData` so the extension flow is unaffected. The legacy `LastPlayedStore.lastPlayedURL()` path (used by `ResumeAbbayIntent`) still has the security-scoped URL limitation. Acceptable: documented as a parallel deferred fix.
- **Extension build dependency on entitlements.** A misconfigured App Group entitlement surfaces as `UserDefaults(suiteName:) == nil` at runtime in the extension. `AppGroup.swift`'s `fatalError` catches it immediately in development; CI build smoke test should exercise the extension's `LibrarySnapshotReader.read()` to surface any misconfiguration before merge.
- **`com.apple.developer.siri` capability + App Store review.** Adds a capability to the main app; profile regen needed. Spotify, YouTube Music, Audible all ship this; no documented App Store review issue.

## Open implementation questions (resolved during plan)

- Exact donation site in `Player.swift` (inside `updatePlayItem` vs in a separate notification hook from `Player.play`). Resolved during plan phase based on what minimizes Player coupling to `Intents` framework.
- Whether to share `FuzzyMatch.swift` source between main app and extension via a symlink/source membership trick OR to duplicate. Default: duplicate, lock to phase-1 vectors via tests on both sides. Revisit during plan.
- Whether to wrap `INInteraction.donate` behind a `IntentDonor` protocol or call directly. Default: protocol-wrapped for test injectability. Confirmed during plan.

## Phase 3 candidates

- Replace JSON snapshot with shared Core Data store in App Group (or `AbbayKit` framework extraction).
- `bookmarkData` round-trip in `LastPlayedStore.lastPlayedURL()` for full security-scoped URL durability.
- iOS 18 AppIntents `AssistantSchemas` (`playMedia` / `playAudiobook`) — see GitHub issue created alongside this spec.
- `LocalizedStringResource` migration for all Siri dialog strings.
- `AppIntentsExtension` target for phase-1 AppIntents (background process for non-Siri AppIntents performance).
- CarPlay scene routing hook if phase 2 observation reveals unwanted iPhone foregrounding.
