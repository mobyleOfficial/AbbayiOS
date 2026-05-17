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
3. **`AppDelegate.fatalError` → graceful launch-state flag.** Replace the existing `try AVAudioSession.sharedInstance().setCategory(.playback)` + `try AVAudioSession.sharedInstance().setActive(true)` / `fatalError` pattern (both calls share one `do/catch` block in `AbbayApp.swift:17-22`) with a flag write to the App Group. **Both throws** (setCategory + setActive) route through the same catch and set `LaunchStateFlag.markUnavailable()`. All five existing AppIntents AND the new extension read the flag; when set, they speak `"Audio temporarily unavailable. Try again in a moment."` instead of crashing.

Plus two UX polish items that the extension enables:

4. **Live disambiguation.** When `fuzzyMatch` returns multiple matches at the top score (see "Disambiguation rule" below), the extension returns `INPlayMediaMediaItemResolutionResult.disambiguation(with:)` instead of `.success(with:)`. Siri prompts the user to pick.
5. **`INPlayMediaIntent` donations.** After every successful play start in the main app — whether triggered by the new extension, an existing AppIntent (including `ResumeAbbayIntent` warm-state same-URL replay), or a manual user tap — donate `INPlayMediaIntent` via `INInteraction(intent:response:).donate()`. Feeds Siri's preferred-media-app learning so `"Hey Siri, play Harry Potter"` (no `"on Abbay"`) gradually routes to Abbay for users who play in Abbay regularly. Donation payload is identical across trigger sources (per WWDC19 session 207: Siri's learning model is keyed on payload + count, not trigger source).

### Phase-2 fix coverage (against phase 1 limitations doc)

| # | Phase 1 limitation | Phase 2 fix |
|---|---|---|
| 1 | Cold-start `"play"` → wrong app | `INPlayMediaIntent` extension wins media-router priority |
| 2 | Cold-launch-during-call crash | `LaunchStateFlag` replaces `fatalError`; intent dialogs read flag |
| 3 | `PlayBookByNameIntent` is two-step | `INMediaSearch.mediaName` is arbitrary String; one-shot phrase works |
| 5 | AppShortcut entity-parameter restriction | Bypassed — extension is not AppIntents |
| 9 | No multi-match disambiguation | `INPlayMediaMediaItemResolutionResult.disambiguation(with:)` |

Limitations #4 (security-scoped URL round-trip), #6 (iOS 17 minimum), #7 (CarPlay scene routing), #8 (English-only dialogs), #10 (AppShortcuts indexing requires one launch), #11 (`IntentDialog` not introspectable), #12 (`"Abbay"` STT phonetic ambiguity) are unchanged from phase 1. #4's `bookmarkData` round-trip is partially addressed here — the snapshot carries the persisted `AudioModel.bookmarkData` field where present. The existing `AudioModel.bookmarkData` field is currently empty for books imported under phase 1 (per phase-1 limitation #4 — v1 didn't change it); phase 2 lazily populates it as books are played (see "bookmarkData population" below). The legacy `LastPlayedStore.lastPlayedURL()` `absoluteString` path is unchanged; a future phase migrates it.

## Non-goals (deferred to phase 3 / later)

- **Full `AbbayKit` framework extraction.** Phase 2 uses a JSON snapshot in App Group `UserDefaults` and minimal source-sharing (a single `FuzzyMatch.swift` file added to both target memberships, OR duplicated — decided during plan). The framework extraction path is deferred to phase 3 once the snapshot-and-handleInApp wire protocol is validated on-device. Trigger for phase 3: concrete need for in-extension playback, materially larger shared state, or maintenance pain from the duplication.
- **AppIntents `AssistantSchemas`** (`playMedia` / `playAudiobook`). Captured as a GitHub issue on AbbayiOS for a future phase. Apple Intelligence-eligible devices only; additive on top of the current AppIntents stack.
- **`AppIntentsExtension` target** for the phase-1 AppIntents. Still useful for non-Siri AppIntents background execution, but not required by `INPlayMediaIntent` (which has its own extension already).
- **Localization of all Siri dialog strings.** Both phase-1 dialogs and the new phase-2 dialogs (`"Audio temporarily unavailable"`, `"No audiobook matches '<input>'"`, etc.) stay English. Future migration swaps `static let` constants to `LocalizedStringResource`; phase-2 spec is structured so this swap is additive.
- **Security-scoped URL `bookmarkData` round-trip in the legacy `LastPlayedStore.lastPlayedURL()` path** used by `ResumeAbbayIntent`. Independent fix; not blocking phase 2 since the snapshot/extension path carries `bookmarkData` per the rules below.
- **CarPlay-specific scene routing hooks.** Added only if phase-2 on-device CarPlay observation reveals unwanted iPhone foregrounding.
- **`"Abbay"` STT phonetic ambiguity remedy** (e.g. `CFBundleDisplayName` rename). Needs marketing call; out of scope.
- **`INMediaItem` artwork in Siri lock-screen sheet.** Spec opted to ship phase 2 with `artwork: nil` to keep the snapshot footprint small. The Siri confirmation sheet shows a blank tile. `AudioModel.imageData` exists; surfacing it via `INImage(imageData:)` is a low-effort phase-3 follow-up. Trade-off is one blank-tile generation in exchange for not encoding imageData (potentially 100KB+ per book) into the JSON snapshot.

## Architecture

### Target topology

```
Abbay.xcodeproj
├── Abbay (app)
│   ├── existing code
│   ├── Core/AppGroup.swift                NEW
│   ├── Core/LibrarySnapshotWriter.swift   NEW
│   ├── Core/LaunchStateFlag.swift         NEW
│   ├── Core/IntentDonor.swift             NEW
│   ├── Core/LastPlayedStore.swift         EDIT (migrate to App Group)
│   ├── Core/Player/Player.swift           EDIT (donation hook + flag clear in play())
│   ├── Intents/AbbayIntents.swift         EDIT (LaunchStateFlag reads in perform())
│   ├── AbbayApp.swift                     EDIT (AppDelegate: replace fatalError, add handle())
│   └── View/MediaListView/
│       ├── MediaListViewModel.swift       EDIT (snapshot writes; new importAudio method)
│       └── DocumentPickerView.swift       EDIT (route import through view model)
└── AbbayIntents (app-extension)           NEW TARGET
    ├── IntentHandler.swift
    ├── PlayMediaIntentHandler.swift
    ├── LibrarySnapshotReader.swift
    ├── FuzzyMatch.swift                   (pure helper; source-membership-shared with Abbay target OR duplicated — plan decides)
    ├── PlayMediaIntent.intentdefinition   (custom no-match Response with input echo)
    ├── Info.plist
    └── AbbayIntents.entitlements          (App Group)
```

Note: `AppDelegate` is a class defined inside `Abbay/AbbayApp.swift` (not a separate `AppDelegate.swift` file). All phase-2 `AppDelegate` edits land in `AbbayApp.swift`.

### Cross-process state (App Group `group.com.edyuto.abbay`)

Single `UserDefaults(suiteName:)` keyed namespace. Three values:

| Key | Type | Writer | Reader |
|---|---|---|---|
| `abbay.lastPlayedAudioURL` | String? | main app (`Player.play(_:)`) | main app, extension |
| `abbay.librarySnapshot.v1` | Data (JSON) | main app (`LibrarySnapshotWriter` on every library load + delete + import + on AppDelegate.handle resolving to nil URL) | extension (`LibrarySnapshotReader`) |
| `abbay.audioSessionUnavailable` | Bool | main app (`AppDelegate.didFinishLaunching` catch branch; cleared by `Player.play(_:)`) | main app (existing AppIntents), extension (resolveMediaItems), main app (AppDelegate.handle) |

Snapshot JSON shape (versioned, future-proof):

```json
{
  "version": 1,
  "updatedAt": "2026-05-17T12:34:56Z",
  "audios": [
    {
      "title": "Harry Potter and the Goblet of Fire",
      "urlString": "file:///...",
      "bookmarkData": "<base64-or-omitted>"
    }
  ]
}
```

`bookmarkData` is included if and only if `AudioModel.bookmarkData` (the existing persisted field on the model) is non-empty for that book at snapshot-write time. See "bookmarkData population" below.

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

### Disambiguation rule

When multiple library entries match the spoken `mediaName`, the extension returns disambiguation per this algorithm:

```
candidates = all entries with score equal to the TOP score (strict equality, not banded)
if candidates.count == 1:
  return .success(with: [candidate])
elif candidates.count <= 5:
  return .disambiguation(with: candidates ordered by lastPlayedURL-first, then library index ASC)
else:  // > 5 share the top score — Siri TTS would choke
  return .success(with: [first per same tiebreak as 1-result case])
```

Cap of 5 is Apple's typical Siri-prompted list size. The `>5` fallback preserves "always play something" behavior over "ask the user to choose from 12 books".

### `LaunchStateFlag` lifecycle

- **Set:** `AppDelegate.didFinishLaunching` catch branch in `AbbayApp.swift` covers BOTH `setCategory(.playback)` and `setActive(true)` throws (they share one `do/catch`). Either throw routes to `LaunchStateFlag.markUnavailable()`.
- **Cleared:** at the END of `Player.play(_:)`, AFTER `player.play()` has been issued. NOT inside `updatePlayItem` — `updatePlayItem` only runs when `url != self.url`, so a same-URL replay (pause/resume, `ResumeAbbayIntent` warm-state) would skip the clear. The clear must fire on every successful `play(_:)` call regardless of URL-change.
- **Read by:** extension `resolveMediaItems`, main app `AppDelegate.application(_:handle:completionHandler:)`, all phase-1 AppIntent `perform()` methods.
- Expected lifetime: cleared on the next successful play. A stale `true` value persists only if the user kills the app while the flag is set AND never plays anything before next Siri invocation — acceptable; user gets the graceful dialog instead of a crash.

### bookmarkData population

The snapshot's `bookmarkData` field reads `AudioModel.bookmarkData` (the existing persisted field on the model). Three population paths:

1. **Books imported under phase 1 (pre-phase-2 install):** `bookmarkData` is empty (phase-1 limitation #4). Snapshot writes `bookmarkData: null` for these books. Extension flow falls back to `URL(string: urlString)`. The first time the user plays such a book in-app under phase 2, `Player.updatePlayItem` populates `AudioModel.bookmarkData` via `url.bookmarkData(options: .minimalBookmark)` (this is a new line in `updatePlayItem`), persists the model via `SaveAudioUseCase`, and the next snapshot write carries it. Within a few plays per book, all books migrate.
2. **Books imported under phase 2 (or later):** the import path (`MediaListViewModel.importAudio`) computes `bookmarkData` at import time while the picker's security-scoped URL is still accessible, and persists it on the model. First snapshot write carries it.
3. **`AudioModel.bookmarkData` migration:** no batch migration in phase 2. Existing books migrate lazily on play (path 1).

This makes phase 2 partially address phase-1 limitation #4: the extension's `handle` flow has reliable URL access for any book played at least once under phase 2; books never played remain on the `URL(string:)` fallback (functional but loses iCloud-not-downloaded gracefully via `LoadAudioUseCase.execute(url:)` returning nil).

## Data flow

### Cold-start `"Hey Siri, play Harry Potter and the Goblet of Fire on Abbay"`

1. Siri parses utterance → media-domain router. Sees Abbay registered as `INPlayMediaIntent` provider → loads `AbbayIntents` extension.
2. Extension's `IntentHandler.handler(for: intent: INPlayMediaIntent)` returns `PlayMediaIntentHandler()`.
3. Siri calls `PlayMediaIntentHandler.resolveMediaItems(for: intent, with: completion)`.
4. Handler:
   - `LaunchStateFlag.isUnavailable()` first. If true → `completion([.unsupported(forReason: .unsupportedMediaType)])`. Siri then calls `handle(intent:completion:)` (resolveMediaItems returning all-unsupported still routes through `handle` — Apple's documented behavior for this Resolution Result kind, confirmed in phase-1 research). Handler returns `INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil)` with the custom Response template from `.intentdefinition` that speaks `"Audio temporarily unavailable. Try again in a moment."`. STOP.
   - `LibrarySnapshotReader.read()` → `[LibraryEntry]`. If empty → same shape as no-match below but with `"Add a book in Abbay first."` Response template.
   - `fuzzyMatch(input: intent.mediaSearch?.mediaName ?? "", audios: entries, lastPlayedURL: lastPlayedURL)` — returns the disambiguation candidates list per the rule above.
     - **0 matches** → `completion([.unsupported(forReason: .unsupportedMediaType)])`. Siri calls `handle`; handler returns `INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil)` with custom Response `"No audiobook matches '<input>'."` (input echoed via Response parameter on the `.intentdefinition`).
     - **1 match** → `completion([.success(with: INMediaItem(identifier: urlString, title: title, type: .audioBook, artwork: nil))])`.
     - **2–5 matches at top score** → `completion([.disambiguation(with: matches.map(toINMediaItem))])`. Siri prompts `"Did you mean A, B, or C?"`. User picks. Siri re-invokes `resolveMediaItems` with the chosen item already populated in `intent.mediaItems`; handler returns `.success(with:)`.
     - **>5 matches at top score** → fall through to single-best per tiebreak, return `.success(with: [best])`.
5. Siri calls `handle(intent:completion:)`. Handler returns `INPlayMediaIntentResponse(code: .handleInApp, userActivity: nil)` — per Apple docs, audio playback uses `.handleInApp` (NOT `.continueInApp`); the system background-launches the host app and forwards the intent. (The no-match / unavailable cases above return `.failureUnknownMediaType` from `handle` instead, with custom Response.)
6. iOS background-launches Abbay. `AppDelegate.didFinishLaunching` (inside `AbbayApp.swift`) runs:
   - Existing `DependencyContainer.configure()` (synchronous, non-throwing).
   - Existing `do { try setCategory(.playback); try setActive(true) } catch { ... }`. On throw of EITHER call: `LaunchStateFlag.markUnavailable()` then `return true` — NO `fatalError`.
7. iOS calls `UIApplicationDelegate.application(_: app, handle intent: INIntent, completionHandler:)` on the main app's `AppDelegate`.
8. `AppDelegate.application(_:handle:completionHandler:)`:
   - `LaunchStateFlag.isUnavailable()` → `completionHandler(INPlayMediaIntentResponse(code: .failureUnknownMediaType))`. Done.
   - Else: `intent.mediaItems?.first?.identifier` → resolve to `URL`. Prefer `bookmarkData` lookup (read the snapshot entry by `urlString`; if its `bookmarkData` is non-empty, resolve via `URL(resolvingBookmarkData:, options: .withoutUI, ...)`). Fall back to `URL(string: identifier)`.
   - Load `AudioModel` via existing `LoadAudioUseCase.execute(url:)`. Nil → completion with `INPlayMediaIntentResponse(code: .failureUnknownMediaType)`; if the URL equals `LastPlayedStore.lastPlayedURL()`, clear it first; ALSO refresh the snapshot (`LibrarySnapshotWriter.write(audios: loadAllAudios.execute())`) so the deleted entry stops misrouting future Siri invocations.
   - `DependencyContainer.shared.player.play(&model)`. (Player.play internally clears `LaunchStateFlag`, donates the intent, and saves `LastPlayedStore` — see "Player.play donation site" below.)
   - `completionHandler(INPlayMediaIntentResponse(code: .success))`.

### Warm-state `"Hey Siri, play X on Abbay"` (app already running)

Same path. iOS still routes through the extension's `resolveMediaItems`, then through main app's `handle`. Main app process is already alive; `didFinishLaunching` does not re-run. `LaunchStateFlag` likely already cleared by an earlier playback cycle.

### Manual play tap

User taps a book in the app. `Player.play(&model)` runs. After `player.play()` is issued (NOT inside `updatePlayItem`), the donation hook fires: `IntentDonor.shared.donatePlayMedia(model:)`. Implementation synthesizes an `INPlayMediaIntent` with `mediaItems: [INMediaItem(identifier: model.url.absoluteString, title: model.title, type: .audioBook)]` + `mediaSearch: INMediaSearch(mediaType: .audioBook, mediaName: model.title)`, wraps in `INInteraction(intent:response:)`, calls `.donate`. Same payload regardless of trigger source.

### Existing AppIntent (`ResumeAbbayIntent` etc.)

Top of `perform()` reads `LaunchStateFlag.isUnavailable()`. True → return `"Audio temporarily unavailable..."` dialog. False → existing phase-1 behavior. On success, `Player.play(_:)` runs the same donation hook regardless of whether `updatePlayItem` actually swapped the item — `ResumeAbbayIntent`'s common case (resume the already-loaded last-played URL) hits the same-URL branch in `Player.play`, but the donation site is outside `updatePlayItem`, so it still fires.

### Player.play donation site

`Player.play(_:)` (in `Abbay/Core/Player/Player.swift`) is extended at the END of the method, AFTER `player.play()` is called. The added lines (in order, all unconditional on URL-change):
1. `LaunchStateFlag.clear()` — audio session is by definition available now.
2. `LastPlayedStore.save(url: model.url)` — moved out of `updatePlayItem` to the outer scope so same-URL replays also update the timestamp. (Inside `updatePlayItem` it was only firing on URL change; same-URL replays leave the store stale.)
3. `AudioModel.bookmarkData` population on first-play (if currently empty) — see "bookmarkData population".
4. `IntentDonor.shared.donatePlayMedia(model:)` — donate INPlayMediaIntent.

Step 2 is moved (not duplicated) — the old call inside `updatePlayItem` is removed. Behavior change: previously, `updatePlayItem` saved to `LastPlayedStore` even before `player.play()`; now save happens after `player.play()` has been issued. Acceptable trade-off: the new ordering means a same-URL replay actually refreshes the store (previously didn't), and the cost is a sub-millisecond delay between `player.play()` and the `UserDefaults.set` (no observable impact).

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

**`PlayMediaIntentHandler.swift`** — `~120 lines`:
```swift
final class PlayMediaIntentHandler: NSObject, INPlayMediaIntentHandling {
    func resolveMediaItems(for intent: INPlayMediaIntent,
                           with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void)
    func handle(intent: INPlayMediaIntent,
                completion: @escaping (INPlayMediaIntentResponse) -> Void)
}
```

`resolveMediaItems` reads `LaunchStateFlag` first, then `LibrarySnapshotReader`, runs `fuzzyMatch`, returns the appropriate `INPlayMediaMediaItemResolutionResult` array per the table in §Data flow §Cold-start step 4 + disambiguation rule.

`handle` branches:
- If `LaunchStateFlag.isUnavailable()` → `INPlayMediaIntentResponse(code: .failureUnknownMediaType)` with the unavailable Response template.
- If `intent.mediaItems` is empty (resolveMediaItems returned all-unsupported for no-match) → `INPlayMediaIntentResponse(code: .failureUnknownMediaType)` with the no-match Response template (input echoed via `INMediaSearch.mediaName`).
- Else → `INPlayMediaIntentResponse(code: .handleInApp)` — system background-launches the host app.

The extension never plays audio itself.

**`LibrarySnapshotReader.swift`** — `~40 lines`. Decodes `LibrarySnapshot` JSON from App Group `UserDefaults`. Exposes `static func read() -> [LibraryEntry]` returning empty array if missing/malformed.

**`FuzzyMatch.swift`** — duplicates the existing pure helper from `Abbay/Intents/AbbayIntents.swift` (or is shared via Xcode source-target-membership; decided during plan). Same normalization rules: `&`→`and`, lowercase, strip punctuation, collapse whitespace, trim. Same scoring: 3 exact, 2 prefix, 1 contains, 0 none. Same tiebreak: last-played first, then library index ascending. **One behavior change for phase 2:** new `matchAll(input:audios:lastPlayedURL:) -> [AudioModel]` variant returns ALL entries at the top score (sorted by tiebreak) rather than just the single best — for the disambiguation path. Existing `fuzzyMatch(input:audios:lastPlayedURL:) -> AudioModel?` keeps its single-result signature for the phase-1 `PlayBookByNameIntent` flow. Both share normalization + scoring code paths; split at the final reduction step.

**`PlayMediaIntent.intentdefinition`** — defines a custom Response with templates for three failure modes:
1. `"Audio temporarily unavailable. Try again in a moment."` (no parameter)
2. `"No audiobook matches '<input>'."` (interpolates `INMediaSearch.mediaName`)
3. `"Add a book in Abbay first."` (no parameter)

Defining the Response in an `.intentdefinition` is the only way to get a custom no-match dialog with input echo for the legacy SiriKit Media domain ([source: phase 1 research](../research/2026-05-17-sirikit-media-providers.md#why-audioplaybackintent--appentity-cannot-match-the-ux)).

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

The `fatalError` here is intentional and is fundamentally different from the one being removed from `AbbayApp.swift`: this fires only if the entitlement is misconfigured at build time, which would surface immediately in development. The removed `fatalError` fires on a transient runtime condition (audio session contention) that production users hit on every cold launch during a phone call.

**`Abbay/Core/LibrarySnapshotWriter.swift`** — `~50 lines`. Encodes `[AudioModel]` to `LibrarySnapshot` JSON and writes to `AppGroup.defaults`. Called from `MediaListViewModel` after library load + delete + import, AND from `AppDelegate.handle` after a nil-URL resolve (to evict stale entries). Includes `bookmarkData` field only when `AudioModel.bookmarkData` is non-empty.

**`Abbay/Core/LaunchStateFlag.swift`** — `~25 lines`:
```swift
enum LaunchStateFlag {
    static func markUnavailable()
    static func clear()
    static func isUnavailable() -> Bool
}
```
All operations route through `AppGroup.defaults` keyed at `abbay.audioSessionUnavailable`.

**`Abbay/Core/IntentDonor.swift`** — `~40 lines`:
```swift
protocol IntentDonorProtocol {
    func donatePlayMedia(model: AudioModel)
}

final class IntentDonor: IntentDonorProtocol {
    static let shared: IntentDonorProtocol = IntentDonor()
    func donatePlayMedia(model: AudioModel)  // builds INPlayMediaIntent, calls INInteraction.donate
}
```
Protocol-wrapped so tests can inject a mock and lock the donation behavior without hitting the real Intents framework.

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

**`Abbay/Core/Player/Player.swift`**:
- Inside `updatePlayItem` (line 158-212 in current source): REMOVE the existing `LastPlayedStore.save(url: url)` call at line 172. (Moved to `play(_:)` outer scope — see below.)
- ADD inside `updatePlayItem` after `hasSecurityAccess = url.startAccessingSecurityScopedResource()` (line 169): if `hasSecurityAccess && item.bookmarkData == nil`, attempt `let bookmark = try? url.bookmarkData(options: .minimalBookmark)`; if non-nil, mutate `model.bookmarkData = bookmark` and persist via `try? saveAudioUseCase.execute(model)`. This is the lazy bookmarkData migration site.
- Inside `play(_:)` (line 85-99), AFTER `player.play()` is called (line 97), ADD in order:
  1. `LaunchStateFlag.clear()`
  2. `if let url = model.url { LastPlayedStore.save(url: url) }`
  3. `IntentDonor.shared.donatePlayMedia(model: model)`

**`Abbay/AbbayApp.swift`** (NOT a new file — this is where `AppDelegate` already lives):
- Replace the `do { try setCategory; try setActive } catch { fatalError(...) }` block (lines 17-22) with the same `do { ... } catch { LaunchStateFlag.markUnavailable() }` shape. Do not re-raise. Do not crash.
- Implement `func application(_ app: UIApplication, handle intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void)` per §Data flow §Cold-start step 8.

**`Abbay/Intents/AbbayIntents.swift`** — top of each `perform()` in all five phase-1 intents:
```swift
guard !LaunchStateFlag.isUnavailable() else {
    return .result(dialog: IntentDialog(Self.audioUnavailableDialog))
}
```
With `static let audioUnavailableDialog = "Audio temporarily unavailable. Try again in a moment."` added once (e.g., on a shared `IntentDialogs` namespace).

**`Abbay/View/MediaListView/MediaListViewModel.swift`**:
- Add `func importAudio(from urls: [URL])` that mutates `audioList` AND triggers a snapshot write AND `AbbayAppShortcuts.updateAppShortcutParameters()`. Bookmark data computed at import time (while picker URLs are accessible) and persisted on the model.
- After `loadAllAudios` and `deleteAudio`, add `LibrarySnapshotWriter.write(audios: audioList)` calls alongside the existing shortcut-parameter update.

**`Abbay/View/MediaListView/DocumentPickerView.swift`** — replace the direct `view.selectedFiles.append(...)` mutation with a call to `view.viewModel.importAudio(from: urls)`. Routes import through the view model so the snapshot write is hit on import, fixing the otherwise-stale-on-just-imported-book Siri case.

**`project.yml`** — add the `AbbayIntents` target, App Group entitlement on both targets, Siri entitlement + `NSSiriUsageDescription` on main app.

## Tests

### New target `AbbayIntentsTests`

Lives in `AbbayIntentsTests/`, runs in the extension's build scheme. All tests use a temporary `UserDefaults(suiteName:)` injected via the `LibrarySnapshotReader`/`LaunchStateFlag` test seams.

- `PlayMediaIntentHandlerTests.resolveMediaItems_singleMatch_returnsSuccess`
- `PlayMediaIntentHandlerTests.resolveMediaItems_twoToFiveMatchesAtTopScore_returnsDisambiguation`
- `PlayMediaIntentHandlerTests.resolveMediaItems_moreThanFiveMatchesAtTopScore_returnsSingleBest`
- `PlayMediaIntentHandlerTests.resolveMediaItems_noMatch_returnsUnsupported_thenHandleReturnsFailureWithNoMatchDialog`
- `PlayMediaIntentHandlerTests.resolveMediaItems_emptyLibrary_returnsUnsupported_thenHandleReturnsFailureWithEmptyLibraryDialog`
- `PlayMediaIntentHandlerTests.resolveMediaItems_audioSessionUnavailableFlag_returnsUnsupported_thenHandleReturnsFailureWithUnavailableDialog`
- `PlayMediaIntentHandlerTests.handle_singleMatchPath_returnsHandleInApp`
- `ExtensionFuzzyMatchTests` — exact / prefix / contains / no-match / punctuation strip / `&`→`and` normalization / last-played tiebreak / multi-match same-score → all results / multi-match different scores → only top score — same vectors as phase-1's `FuzzyMatchTests`, locked to the extension copy of the helper.
- `LibrarySnapshotReaderTests.read_validJSON_returnsEntries`
- `LibrarySnapshotReaderTests.read_missingValue_returnsEmpty`
- `LibrarySnapshotReaderTests.read_malformedJSON_returnsEmpty`

### Extending `AbbayTests` (main app)

- `AppDelegateTests.audioSessionSetActiveThrow_setsFlag_doesNotCrash` — replaces phase 1's documented crash test; verifies the flag is set and `didFinishLaunching` returns normally.
- `AppDelegateTests.audioSessionSetCategoryThrow_setsFlag_doesNotCrash` — same for setCategory throw path.
- `AppDelegateTests.handlePlayMediaIntent_callsPlayer_donates`
- `AppDelegateTests.handlePlayMediaIntent_audioUnavailable_returnsFailure_doesNotCallPlayer`
- `AppDelegateTests.handlePlayMediaIntent_loadAudioReturnsNil_returnsFailure_clearsLastPlayedIfMatched_refreshesSnapshot`
- `LibrarySnapshotWriterTests.write_decodableByExtensionReader_roundTrip` — locks the JSON shape contract; the writer writes, the reader reads back identical entries (run from the main-app test target; reader code shared via a thin source-file linkage so the test compiles).
- `LibrarySnapshotWriterTests.write_afterDelete_removesEntry`
- `LibrarySnapshotWriterTests.write_excludesBookmarkDataWhenModelEmpty`
- `LibrarySnapshotWriterTests.write_includesBookmarkDataWhenModelPopulated`
- `LastPlayedStoreTests.migration_standardToAppGroup_seedThenWrite_zeroLoss` — verifies the seed-then-write ordering preserves a pre-existing `.standard` value when the suite is empty AND does not clobber a fresh suite write.
- `LaunchStateFlagTests.markUnavailable_thenClear_roundTrip`
- `LaunchStateFlagTests.isUnavailable_defaultsFalse`
- `PlayerTests.play_sameURLReplay_donatesEachTime` — locks the donation-on-every-play promise even when `updatePlayItem` is skipped.
- `PlayerTests.play_firstPlayOfBookWithoutBookmark_populatesBookmarkData` — lazy bookmark migration path.
- Existing `IntentTests` extended: each phase-1 intent's `perform()` test gets a sibling case asserting the `LaunchStateFlag.isUnavailable() == true` branch returns the unavailable dialog and does NOT call `Player`.
- Existing `IntentTests` extended: assertion that `ResumeAbbayIntent`-driven `Player.play(_:)` triggers `IntentDonor.donatePlayMedia` even when `updatePlayItem` is skipped (warm-state same-URL case).

## Manual verification checklist

Plan task `Manual on-device verification` will spell these out; capturing the headline cases here:

- **Headline:** Kill Abbay. `"Hey Siri, play Harry Potter and the Goblet of Fire on Abbay"`. Expected: app background-launches, starts that book. ✅ No longer routes to YouTube Music.
- **Disambiguation:** Library has two Harry Potter books. Kill Abbay. `"Hey Siri, play Harry Potter on Abbay"`. Expected: Siri prompts `"Did you mean Sorcerer's Stone or Chamber of Secrets?"` → user picks → plays.
- **Many-match cap:** Library has six books containing the word "audiobook". Kill Abbay. `"Hey Siri, play audiobook on Abbay"`. Expected: Siri plays the last-played (tiebreak winner), no 6-way disambiguation prompt.
- **Graceful launch:** Kill Abbay. Start an active phone call. `"Hey Siri, play in Abbay"`. Expected: spoken `"Audio temporarily unavailable. Try again in a moment."`. NO crash. Verify via Console.app that no `AVAudioSession` `fatalError` is logged.
- **Background-launch budget:** Invoke Siri 6+ times in close succession during an active phone call (all should hit the unavailable dialog). Confirm iOS doesn't silently stop background-launching the app after the unavailable responses. If it does, document the threshold; the spec's expectation is that iOS will keep honoring the extension because we return early from `resolveMediaItems` (no wasted background-launch) — but verify on-device.
- **Donation learning:** Fresh device, install Abbay phase 2. Play a book manually 3+ times across separate sessions. Wait. `"Hey Siri, play Harry Potter"` (no `"on Abbay"`). Expected behavior: after enough donations, Siri starts routing to Abbay. Acceptable: this may take time and is system-managed.
- **Same-URL replay donation:** Play a book. Pause. Tap play again on the same book. Inspect `IntentDonor` test seam (or logs) — donation should fire on the second play too. Verifies the donation-on-every-play promise.
- **`ResumeAbbayIntent` warm-state donation:** While a book is playing, say `"Hey Siri, pause Abbay"`, then `"Hey Siri, continue audiobook in Abbay"`. Inspect: donation fires on the resume even though `updatePlayItem` was skipped.
- **No regression:** Phase-1 phrases (`"continue audiobook in Abbay"`, `"pause Abbay"`, `"next chapter in Abbay"`, `"previous chapter in Abbay"`) still work cold-start.
- **Delete staleness recovery:** Play book A; delete it from the library; immediately kill the app; say `"Hey Siri, play A on Abbay"`. Expected: Siri speaks `"Cannot find that audiobook..."`. Subsequent Siri invocations for A also fail gracefully (snapshot refreshed on the first failure).
- **Migration:** Upgrade install. Existing user with `LastPlayedStore` in `.standard`. First Siri invocation reads correct last-played; subsequent main-app play writes to App Group; extension reads same value.
- **Lazy bookmark population:** Cold-start `"Hey Siri, play <book never played under phase 2> on Abbay"`. Extension resolves via `URL(string:)` fallback. Main app plays. Snapshot rewrites with populated `bookmarkData` (verifiable via `defaults read` on the App Group suite). Second Siri invocation uses the bookmark path.
- **CarPlay:** Connect device to CarPlay. Repeat headline and pause/next chapter phrases. Confirm playback in CarPlay UI; note whether iPhone foregrounds (acceptable either way for phase 2; deferred CarPlay hook if unwanted foregrounding).

## Risks

- **`INPlayMediaIntent` mediaSearch reliability.** Apple Developer Forums thread [FB14872048](https://developer.apple.com/forums/thread/762196) (Aug 2024) reports occasional `mediaSearch.mediaName` truncation on long titles. Mitigation: our titles are short relative to song titles; phase-2 includes a manual checklist case verifying a long book title (`"Harry Potter and the Goblet of Fire"`) round-trips correctly. Escalate to a follow-up issue if hit.
- **Donation rate vs Siri's learning model.** Apple does not publish the threshold for `"play <X>"` (no app name) to route to a third-party media app. WWDC21 session 10231 documents donation cadence but not the routing model. Phase-2 donates on every successful play start (extension + AppIntents + manual taps); this matches Spotify-class apps. Risk: if Apple changes the model in a future iOS update, the no-app-name routing degrades silently. Mitigation: manual checklist tracks behavior; non-blocking for phase 2 since the "on Abbay" case is the headline.
- **iOS background-launch budget for `INPlayMediaIntent` extensions.** iOS rate-limits how often the host app will be background-launched from an extension's `.handleInApp` response. After repeated failures (e.g., user invokes Siri during many consecutive phone calls and gets the unavailable dialog each time), iOS may stop background-launching Abbay at all for a window. Mitigation: when `LaunchStateFlag.isUnavailable()` is true, the extension returns `.failureUnknownMediaType` from `handle` instead of `.handleInApp` — no host-app launch is requested, no budget consumed. Manual checklist verifies this on-device.
- **App Group migration on existing installs.** The seed-then-write ordering covers the standard upgrade path. Edge case: user kills the app between the upgrade and first playback, then triggers Siri before re-launching. Extension reads from the App Group — which is empty — and `LastPlayedStore.lastPlayedURL()` returns nil. Handler still routes via `mediaSearch.mediaName` correctly; user sees a `"No audiobook matches..."` only if they say `"play in Abbay"` (no specific book) before re-launching. Acceptable: documented in the manual checklist; not a regression vs phase 1.
- **JSON snapshot freshness window.** Snapshot is written on library load + delete + import + AppDelegate.handle nil-URL refresh. Edge case: user imports a book, kills app before the write completes, triggers Siri. Window is sub-millisecond (`UserDefaults.set` is synchronous, atomic). Symmetric DELETE staleness is handled by the AppDelegate.handle nil-URL snapshot refresh (above). Acceptable.
- **`bookmarkData` round-trip for never-played books.** Books imported pre-phase-2 and not yet played under phase 2 ship snapshot entries without bookmarkData. The extension's `handle` flow falls back to `URL(string: identifier)`. The legacy security-scoped URL semantics apply (`URL(string:)` does NOT round-trip the scope) — the URL is technically still openable but `LoadAudioUseCase` may return nil if iCloud-not-downloaded. Mitigation: documented in the manual checklist as "lazy bookmark population"; first play migrates the book; sub-second user-visible cost.
- **Extension build dependency on entitlements.** A misconfigured App Group entitlement surfaces as `UserDefaults(suiteName:) == nil` at runtime in the extension. `AppGroup.swift`'s `fatalError` catches it immediately in development; CI build smoke test should exercise the extension's `LibrarySnapshotReader.read()` to surface any misconfiguration before merge.
- **`com.apple.developer.siri` capability + App Store review.** Adds a capability to the main app; profile regen needed. Spotify, YouTube Music, Audible all ship this; no documented App Store review issue.

## Open implementation questions (deferred to plan)

- **Whether to share `FuzzyMatch.swift` source between main app and extension via Xcode source-target-membership (one file in both targets' compile-sources lists) OR to duplicate the file in both directories.** Plan-phase decision based on which produces cleaner xcodegen output. Both meet the spec's correctness contract. Tests in both `AbbayTests` and `AbbayIntentsTests` lock identical fuzzy-match vectors regardless.

(Previously open: donation site in Player.swift and IntentDonor protocol — pinned above in §Components §Player.play donation site and §Main-app new files. Previously open: manual vs Siri-triggered donation differences — pinned: identical payload, per WWDC19 session 207.)

## Phase 3 candidates

- Replace JSON snapshot with shared Core Data store in App Group (or `AbbayKit` framework extraction).
- `bookmarkData` round-trip in `LastPlayedStore.lastPlayedURL()` for full security-scoped URL durability.
- iOS 18 AppIntents `AssistantSchemas` (`playMedia` / `playAudiobook`) — see GitHub issue created alongside this spec.
- `LocalizedStringResource` migration for all Siri dialog strings.
- `AppIntentsExtension` target for phase-1 AppIntents (background process for non-Siri AppIntents performance).
- CarPlay scene routing hook if phase 2 observation reveals unwanted iPhone foregrounding.
- `INMediaItem` artwork in Siri lock-screen sheet — surface `AudioModel.imageData` via `INImage(imageData:)`. Adds JSON-snapshot footprint or a secondary file-based artwork store; weighed against the blank-tile UX cost.
