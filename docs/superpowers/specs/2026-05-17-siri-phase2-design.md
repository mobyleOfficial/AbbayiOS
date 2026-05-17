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
3. **`AppDelegate.fatalError` → graceful launch-state flag with retry-on-play recovery.** Replace the existing `try AVAudioSession.sharedInstance().setCategory(.playback)` + `try AVAudioSession.sharedInstance().setActive(true)` / `fatalError` pattern (both calls share one `do/catch` block in `AbbayApp.swift:17-22`) with a flag write to the App Group. **Both throws** (setCategory + setActive) route through the same catch and set `LaunchStateFlag.markUnavailable()`. All five existing AppIntents AND the new extension read the flag; when set, they speak `"Audio temporarily unavailable. Try again in a moment."` instead of crashing. **Recovery:** `Player.play(_:)` re-attempts `setCategory` + `setActive` at the top of every play; on success it clears the flag, on throw it returns early without playing (caller's flag-gate check spoke the dialog, so silent no-op is acceptable defense-in-depth).

Plus two UX polish items that the extension enables:

4. **Live disambiguation.** When `fuzzyMatch` returns multiple matches at the top score (see "Disambiguation rule" below), the extension returns `INPlayMediaMediaItemResolutionResult.disambiguation(with:)` instead of `.success(with:)`. Siri prompts the user to pick.
5. **`INPlayMediaIntent` donations.** After every successful play start in the main app — whether triggered by the new extension, an existing AppIntent (including `ResumeAbbayIntent` warm-state same-URL replay), or a manual user tap — donate `INPlayMediaIntent` via `INInteraction(intent:response:).donate()`. Feeds Siri's preferred-media-app learning so `"Hey Siri, play Harry Potter"` (no `"on Abbay"`) gradually routes to Abbay for users who play in Abbay regularly. Donation payload is identical across trigger sources (per WWDC19 session 207: Siri's learning model is keyed on payload + count, not trigger source).

### Phase-2 fix coverage (against phase 1 limitations doc)

| # | Phase 1 limitation | Phase 2 fix |
|---|---|---|
| 1 | Cold-start `"play"` → wrong app | `INPlayMediaIntent` extension wins media-router priority |
| 2 | Cold-launch-during-call crash | `LaunchStateFlag` replaces `fatalError`; `Player.play` retries `setActive` |
| 3 | `PlayBookByNameIntent` is two-step | `INMediaSearch.mediaName` is arbitrary String; one-shot phrase works |
| 5 | AppShortcut entity-parameter restriction | Bypassed — extension is not AppIntents |
| 9 | No multi-match disambiguation | `INPlayMediaMediaItemResolutionResult.disambiguation(with:)` |

Limitations #4 (security-scoped URL round-trip), #6 (iOS 17 minimum), #7 (CarPlay scene routing), #8 (English-only dialogs), #10 (AppShortcuts indexing requires one launch), #11 (`IntentDialog` not introspectable), #12 (`"Abbay"` STT phonetic ambiguity) are unchanged from phase 1. #4's `bookmarkData` round-trip is partially addressed here — the snapshot carries the persisted `AudioModel.bookmarkData` field where present. `FileLoader.load(url:)` already populates `AudioModel.bookmarkData` (`FileLoader.swift:51`) for newly-imported books via `url.createBookmarkData()`; phase 1's #4 referred to the legacy `LastPlayedStore.lastPlayedURL()` `absoluteString` path, NOT to the `AudioModel.bookmarkData` field. **Legacy books** — those imported under pre-FileLoader-bookmark versions and stored in Core Data without `bookmarkData` — are migrated lazily in `Player.play(_:)` on first play under phase 2.

## Non-goals (deferred to phase 3 / later)

- **Full `AbbayKit` framework extraction.** Phase 2 uses a JSON snapshot in App Group `UserDefaults` and minimal source-sharing (a single `FuzzyMatch.swift` file added to both target memberships, OR duplicated — decided during plan). The framework extraction path is deferred to phase 3.
- **AppIntents `AssistantSchemas`** (`playMedia` / `playAudiobook`). Captured as a GitHub issue on AbbayiOS for a future phase. Apple Intelligence-eligible devices only; additive on top of the current AppIntents stack.
- **`AppIntentsExtension` target** for the phase-1 AppIntents.
- **Localization of all Siri dialog strings.** Both phase-1 dialogs and the new phase-2 dialogs stay English. Future migration swaps `static let` constants to `LocalizedStringResource`; phase-2 spec is structured so this swap is additive.
- **Security-scoped URL `bookmarkData` round-trip in the legacy `LastPlayedStore.lastPlayedURL()` path** used by `ResumeAbbayIntent`. Independent fix; not blocking phase 2 since the snapshot/extension path carries `bookmarkData` per the rules below.
- **CarPlay-specific scene routing hooks.** Added only if phase-2 on-device CarPlay observation reveals unwanted iPhone foregrounding.
- **`"Abbay"` STT phonetic ambiguity remedy** (e.g. `CFBundleDisplayName` rename). Needs marketing call.
- **`INMediaItem` artwork in Siri lock-screen sheet.** Spec opted to ship phase 2 with `artwork: nil` to keep the snapshot footprint small.

Each phase-3 candidate has a concrete trigger condition listed in the "Phase 3 candidates" section.

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
│   ├── Core/Player/Player.swift           EDIT (retry-setActive, donation, flag clear, lazy bookmark)
│   ├── Intents/AbbayIntents.swift         EDIT (LaunchStateFlag reads in perform())
│   ├── AbbayApp.swift                     EDIT (AppDelegate: replace fatalError, eager seeds, add handle())
│   └── View/MediaListView/
│       ├── MediaListViewModel.swift       EDIT (snapshot writes; new importAudio async method)
│       └── DocumentPicker/DocumentPickerView.swift  EDIT (route import through view model)
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
| `abbay.lastPlayedAudioURL` | String? | main app (`Player.play(_:)`; AppDelegate eager-seed on launch) | main app, extension |
| `abbay.librarySnapshot.v1` | Data (JSON) | main app (`LibrarySnapshotWriter`: on every library load + delete + import + lazy-bookmark-population in `Player.play` + AppDelegate eager-seed on launch + `AppDelegate.handle` resolving to nil URL) | extension (`LibrarySnapshotReader`) |
| `abbay.audioSessionUnavailable` | Bool | main app (`AppDelegate.didFinishLaunching` catch branch; `Player.play(_:)` retry-clear or retry-fail; cleared by successful `setActive`) | main app (existing AppIntents, AppDelegate.handle), extension (resolveMediaItems + handle) |

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

`bookmarkData` is included iff `AudioModel.bookmarkData` is non-empty for that book at snapshot-write time. See "bookmarkData population" below.

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

- Top of each `perform()` reads `LaunchStateFlag.isUnavailable()`. If true, returns `.result(dialog: IntentDialog(Self.audioUnavailableDialog))` immediately. Note this is a fast-path check — `Player.play(_:)` re-attempts setActive defense-in-depth even if the AppIntent gate misses a race.
- They keep handling Shortcuts, widgets, AppShortcuts phrases for non-"play" verbs (`"continue audiobook in Abbay"`, etc.) and the warm-state `"play in Abbay"` case.
- `PlayBookByNameIntent` is NOT retired. Remains the Shortcuts-app path.

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
- **Cleared:** at the TOP of every `Player.play(_:)`. Specifically: `Player.play` always re-attempts `try setCategory(.playback); try setActive(true)` at the top. On success → `LaunchStateFlag.clear()` and continue with playback. On throw → mark flag (idempotent if already set) and **return early without calling `player.play()` or donating**. This is the recovery path. Reasoning: `setActive` is idempotent — calling it when already active is a fast no-op; calling when inactive is the recovery the spec needs. This eliminates the "stale flag set forever" failure mode where audio became available mid-process but the flag never cleared.
- **Read by:** extension `resolveMediaItems` AND `handle` (returns `.failureUnknownMediaType` on flag-set), main app `AppDelegate.application(_:handle:completionHandler:)`, all phase-1 AppIntent `perform()` methods.
- Expected lifetime: cleared on the first successful play after a launch-time flag set, OR on any successful play — flag clear is now driven by the actual `setActive` success, not by an optimistic `player.play()`-was-called signal.

### bookmarkData population

The snapshot's `bookmarkData` field reads `AudioModel.bookmarkData`. Three population paths:

1. **Books imported under FileLoader's existing bookmark-creation logic (`FileLoader.swift:51`):** `AudioModel.bookmarkData` is populated at import time. Snapshot writes carry it.
2. **Legacy books (imported before FileLoader populated bookmarkData):** `bookmarkData` is empty. Snapshot writes `bookmarkData: null` for these. Extension flow falls back to `URL(string: urlString)` for resolve. **Lazy migration:** `Player.play(_:)` (BEFORE `updatePlayItem`) checks: if `model.bookmarkData == nil`, attempts `url.createBookmarkData()` while holding security scope. If non-nil, mutates the `inout model` directly (struct-by-reference via `inout`), persists via `try? saveAudioUseCase.execute(model)`, and refreshes the snapshot via `LibrarySnapshotWriter.write(audios: loadAllAudios.execute())`. Mutation MUST land on the `inout model` (not on a local copy inside `updatePlayItem`) so that `IntentDonor.donatePlayMedia(model:)` later in `play(_:)` donates with the populated model AND `self.model = item` inside `updatePlayItem` (which copies the inout-mutated model) stores the populated copy.
3. **Snapshot refresh after lazy migration:** required so the NEXT Siri invocation against the same book sees the bookmark path. Without this refresh, the snapshot stays stale until the next `MediaListViewModel.loadAllAudios` call.

This makes phase 2 partially address phase-1 limitation #4: the extension's `handle` flow has reliable URL access for any book played at least once under phase 2.

### Eager seeding at AppDelegate launch

After `AVAudioSession.setActive` succeeds in `didFinishLaunching`, perform two one-shot eager seeds (cheap, idempotent, closes the cold-background-launch empty-snapshot window):

1. **`LastPlayedStore` seed:** if `AppGroup.defaults` has no value AND `UserDefaults.standard` has a value for `abbay.lastPlayedAudioURL`, copy `.standard` → AppGroup. Subsequent reads/writes go to AppGroup.
2. **`LibrarySnapshot` seed:** if `AppGroup.defaults` has no value for `abbay.librarySnapshot.v1`, run `LoadAllAudiosUseCase().execute()` and write the result via `LibrarySnapshotWriter.write(audios:)`. This guarantees the extension always sees a current snapshot even on cold-background-launch (where `MediaListView` may never instantiate).

Both seeds are no-ops on subsequent launches (key already present). Combined cost: one extra `UserDefaults.object(forKey:)` lookup plus, on first-post-upgrade launch, one Core Data read + one JSON write.

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
5. Siri calls `handle(intent:completion:)`. Handler returns `INPlayMediaIntentResponse(code: .handleInApp, userActivity: nil)` — per Apple docs, audio playback uses `.handleInApp` (NOT `.continueInApp`); the system background-launches the host app and forwards the intent. (The no-match / unavailable cases return `.failureUnknownMediaType` instead, with custom Response.)
6. iOS background-launches Abbay. `AppDelegate.didFinishLaunching` (inside `AbbayApp.swift`) runs:
   - `DependencyContainer.configure()` (synchronous, non-throwing).
   - `do { try setCategory(.playback); try setActive(true) } catch { LaunchStateFlag.markUnavailable(); return true }`. On throw of EITHER call: flag set, return true, no fatalError.
   - On success: eager-seed `LastPlayedStore` and `LibrarySnapshot` per "Eager seeding" above.
7. iOS calls `UIApplicationDelegate.application(_: app, handle intent: INIntent, completionHandler:)` on the main app's `AppDelegate`.
8. `AppDelegate.application(_:handle:completionHandler:)`:
   - `LaunchStateFlag.isUnavailable()` → `completionHandler(INPlayMediaIntentResponse(code: .failureUnknownMediaType))`. Done.
   - Else: `intent.mediaItems?.first?.identifier` → resolve to `URL`. Prefer `bookmarkData` lookup (read the snapshot entry by `urlString`; if its `bookmarkData` is non-empty, resolve via `URL(resolvingBookmarkData:, options: .withoutUI, ...)`). Fall back to `URL(string: identifier)`.
   - Load `AudioModel` via existing `LoadAudioUseCase.execute(url:)`. Nil → completion with `INPlayMediaIntentResponse(code: .failureUnknownMediaType)`; if the URL equals `LastPlayedStore.lastPlayedURL()`, clear it first; ALSO refresh the snapshot (`LibrarySnapshotWriter.write(audios: loadAllAudios.execute())`) so the deleted entry stops misrouting future Siri invocations.
   - `DependencyContainer.shared.player.play(&model)`. (Player.play internally retries setActive, lazy-populates bookmark if missing, clears the flag, donates the intent, and saves `LastPlayedStore` — see "Player.play sequence" below.)
   - `completionHandler(INPlayMediaIntentResponse(code: .success))`.

### Warm-state `"Hey Siri, play X on Abbay"` (app already running)

Same path. iOS still routes through the extension's `resolveMediaItems`, then through main app's `handle`. Main app process is already alive; `didFinishLaunching` does not re-run.

### Manual play tap

User taps a book in the app. `Player.play(&model)` runs the same sequence as the Siri-triggered path. Donation fires; identical payload (per WWDC19 207).

### Existing AppIntent (`ResumeAbbayIntent` etc.)

Top of `perform()` reads `LaunchStateFlag.isUnavailable()`. True → return `"Audio temporarily unavailable..."` dialog. False → existing phase-1 behavior calls `Player.play(_:)`, which runs the same donation hook (including same-URL replay).

### Player.play sequence (pinned)

`Player.play(_:)` (in `Abbay/Core/Player/Player.swift`) runs in this exact order:

```
func play(_ model: inout AudioModel) {
    guard let url = model.url else { return }

    // Step 1 — defense-in-depth audio session recovery
    do {
        try AVAudioSession.sharedInstance().setCategory(.playback)
        try AVAudioSession.sharedInstance().setActive(true)
        LaunchStateFlag.clear()
    } catch {
        LaunchStateFlag.markUnavailable()
        return  // do not play, do not donate; caller's gate already spoke the dialog
    }

    // Step 2 — lazy bookmark population on the inout model
    if model.bookmarkData == nil {
        if url.startAccessingSecurityScopedResource() {
            model.bookmarkData = url.createBookmarkData()
            url.stopAccessingSecurityScopedResource()
            try? saveAudioUseCase.execute(model)
            librarySnapshotWriter.write(audios: loadAllAudios.execute())
        }
    }

    // Step 3 — existing item-switch path
    if url != self.url {
        saveTime()
        updatePlayItem(model)  // sees the populated bookmarkData
        seek(model.currentTime)
    }

    // Step 4 — playback + post-play side effects (unconditional on URL-change)
    player.play()
    LastPlayedStore.save(url: url)            // moved out of updatePlayItem; fires on every play
    intentDonor.donatePlayMedia(model: model) // identical payload across triggers
}
```

Step 1 makes the `LaunchStateFlag` lifecycle deterministic: a failed launch can recover on any subsequent play attempt (post-call, post-Focus). Step 2's mutation is on the `inout model` parameter, so steps 3 and 4 see the same populated bookmarkData. Step 4's three lines moved out of `updatePlayItem` so they fire on every play, including same-URL replays (closes phase-1 same-URL donation gap).

`updatePlayItem(_ item: AudioModel)` is simplified: it stops accessing the previous security-scoped URL, starts accessing the new one, sets `self.model = item`, wires AVPlayer observers. No bookmark mutation, no `LastPlayedStore.save`, no donation — those moved to `play(_:)`.

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

Behavior per §Data flow §Cold-start steps 4–5 + disambiguation rule.

**`LibrarySnapshotReader.swift`** — `~40 lines`. Decodes `LibrarySnapshot` JSON from App Group `UserDefaults`. Exposes `static func read() -> [LibraryEntry]` returning empty array if missing/malformed.

**`FuzzyMatch.swift`** — duplicates (or shares via target-membership) the existing pure helper from `Abbay/Intents/AbbayIntents.swift`. New `matchAll(input:audios:lastPlayedURL:) -> [AudioModel]` variant returns all entries at top score; existing `fuzzyMatch(...) -> AudioModel?` keeps single-result signature for phase-1 `PlayBookByNameIntent`.

**`PlayMediaIntent.intentdefinition`** — custom Response with three failure templates: `"Audio temporarily unavailable..."`, `"No audiobook matches '<input>'."` (parameter-interpolated), `"Add a book in Abbay first."`.

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

This `fatalError` is intentional: misconfigured entitlement, surfaces immediately in development. Different from the runtime-condition `fatalError` being removed from `AbbayApp.swift`.

**`Abbay/Core/LibrarySnapshotWriter.swift`** — `~60 lines`:
```swift
protocol LibrarySnapshotWriterProtocol {
    func write(audios: [AudioModel])
}

final class LibrarySnapshotWriter: LibrarySnapshotWriterProtocol {
    static let shared: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter()
    func write(audios: [AudioModel])  // encodes JSON, writes to AppGroup.defaults
}
```

Protocol-wrapped for `Player` injection (see Player init below).

**`Abbay/Core/LaunchStateFlag.swift`** — `~25 lines`:
```swift
enum LaunchStateFlag {
    static func markUnavailable()
    static func clear()
    static func isUnavailable() -> Bool
}
```

**`Abbay/Core/IntentDonor.swift`** — `~40 lines`:
```swift
protocol IntentDonorProtocol {
    func donatePlayMedia(model: AudioModel)
}

final class IntentDonor: IntentDonorProtocol {
    static let shared: IntentDonorProtocol = IntentDonor()
    func donatePlayMedia(model: AudioModel)
}
```

### Main-app edits

**`Abbay/Core/LastPlayedStore.swift`** — switch `defaults` to `AppGroup.defaults`. Read-side fallback to `UserDefaults.standard` for the upgrade window. AppDelegate-launch-time eager seed (above) closes the remaining empty-store windows.

```
On read:
  if AppGroup.defaults has no value AND UserDefaults.standard has → return .standard value
  else return AppGroup.defaults value (which may be nil)
On write (main app only):
  if AppGroup.defaults has no value AND .standard has → copy .standard into AppGroup (seed)
  ALWAYS write new value to AppGroup.defaults
```

Note: read-side fallback to `.standard` is meaningful in the MAIN APP only (extension has its own separate `.standard` domain). For the extension cold-launch case (before any main-app launch under phase 2), the `lastPlayedURL` is nil in the App Group — which is acceptable for v1 since `fuzzyMatch.lastPlayedTiebreak` simply has no tiebreak and falls back to library-index ordering. The AppDelegate eager-seed on first main-app launch under phase 2 fixes this for all subsequent extension invocations.

**`Abbay/Core/Player/Player.swift`** — see §Player.play sequence above for the full ordering. Init signature gains two injection seams:

```swift
init(
    saveAudioUseCase: SaveAudioUseCaseProtocol = SaveAudioUseCase(),
    loadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase(),
    intentDonor: IntentDonorProtocol = IntentDonor.shared,
    librarySnapshotWriter: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter.shared
)
```

The new params have sensible defaults so existing call sites compile unchanged. Tests inject mocks for `intentDonor` and `librarySnapshotWriter`.

**`Abbay/AbbayApp.swift`** (NOT a new file — `AppDelegate` already lives here):
- Replace the `do { try setCategory; try setActive } catch { fatalError(...) }` block (lines 17-22) with `do { ... } catch { LaunchStateFlag.markUnavailable(); return true }` shape.
- After the success path of setActive, run eager seeds (LastPlayedStore + LibrarySnapshot) per §Eager seeding.
- Implement `func application(_ app: UIApplication, handle intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void)` per §Data flow §Cold-start step 8.

**`Abbay/Intents/AbbayIntents.swift`** — top of each `perform()` in all five phase-1 intents:
```swift
guard !LaunchStateFlag.isUnavailable() else {
    return .result(dialog: IntentDialog(Self.audioUnavailableDialog))
}
```
`static let audioUnavailableDialog = "Audio temporarily unavailable. Try again in a moment."`

**`Abbay/View/MediaListView/MediaListViewModel.swift`**:
- Add `func importAudio(from urls: [URL]) async`:
  ```swift
  func importAudio(from urls: [URL]) async {
      let newFiles = await fileLoader.load(urls: urls)  // already populates bookmarkData on each
      for file in newFiles where !audioList.contains(where: { $0.url == file.url }) {
          audioList.append(file)
      }
      LibrarySnapshotWriter.shared.write(audios: audioList)
      AbbayAppShortcuts.updateAppShortcutParameters()
  }
  ```
- After `loadAllAudios` and `deleteAudio`, add `LibrarySnapshotWriter.shared.write(audios: audioList)` alongside existing shortcut updates.

**`Abbay/View/DocumentPicker/DocumentPickerView.swift`**:
- Replace the direct `view.selectedFiles.append(file)` mutation (current lines 52-58) with a single call: `Task { await view.viewModel.importAudio(from: urls) }`. Requires `DocumentPickerView` to hold a reference to the view model (currently it holds a `@Binding` to `selectedFiles` only; the binding becomes a view-model reference instead). View model surface is the cleaner pin since the snapshot/shortcut updates now have a single trigger.

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
- `ExtensionFuzzyMatchTests` — exact / prefix / contains / no-match / punctuation strip / `&`→`and` / last-played tiebreak / multi-match same-score (`matchAll`) / multi-match different scores (`matchAll` returns only top score) — same vectors as phase-1's `FuzzyMatchTests`.
- `LibrarySnapshotReaderTests.read_validJSON_returnsEntries`
- `LibrarySnapshotReaderTests.read_missingValue_returnsEmpty`
- `LibrarySnapshotReaderTests.read_malformedJSON_returnsEmpty`

### Extending `AbbayTests` (main app)

- `AppDelegateTests.audioSessionSetActiveThrow_setsFlag_doesNotCrash`
- `AppDelegateTests.audioSessionSetCategoryThrow_setsFlag_doesNotCrash`
- `AppDelegateTests.didFinishLaunching_emptySnapshot_eagerSeedsFromLoadAllAudios`
- `AppDelegateTests.didFinishLaunching_populatedSnapshot_skipsEagerSeed`
- `AppDelegateTests.didFinishLaunching_lastPlayedInStandardOnly_seedsAppGroup`
- `AppDelegateTests.handlePlayMediaIntent_callsPlayer_donatesViaPlayerSideEffect`
- `AppDelegateTests.handlePlayMediaIntent_audioUnavailable_returnsFailure_doesNotCallPlayer`
- `AppDelegateTests.handlePlayMediaIntent_loadAudioReturnsNil_returnsFailure_clearsLastPlayedIfMatched_refreshesSnapshot`
- `LibrarySnapshotWriterTests.write_decodableByExtensionReader_roundTrip`
- `LibrarySnapshotWriterTests.write_afterDelete_removesEntry`
- `LibrarySnapshotWriterTests.write_excludesBookmarkDataWhenModelEmpty`
- `LibrarySnapshotWriterTests.write_includesBookmarkDataWhenModelPopulated`
- `LastPlayedStoreTests.migration_standardToAppGroup_seedThenWrite_zeroLoss`
- `LaunchStateFlagTests.markUnavailable_thenClear_roundTrip`
- `LaunchStateFlagTests.isUnavailable_defaultsFalse`
- `PlayerTests.play_setActiveSucceeds_clearsLaunchStateFlag`
- `PlayerTests.play_setActiveThrows_setsLaunchStateFlag_doesNotCallAVPlayerPlay_doesNotDonate`
- `PlayerTests.play_sameURLReplay_donatesEachTime`
- `PlayerTests.play_firstPlayOfBookWithoutBookmark_populatesBookmarkDataOnInoutModel_refreshesSnapshot`
- `PlayerTests.play_firstPlayOfBookWithBookmark_doesNotRePopulate`
- `MediaListViewModelTests.importAudio_appendsNonDuplicates_writesSnapshot_updatesShortcuts`
- Existing `IntentTests` extended: each phase-1 intent's `perform()` test gets a sibling case asserting the `LaunchStateFlag.isUnavailable() == true` branch returns the unavailable dialog and does NOT call `Player`.
- Existing `IntentTests` extended: assertion that `ResumeAbbayIntent`-driven `Player.play(_:)` triggers `IntentDonor.donatePlayMedia` even when `updatePlayItem` is skipped (warm-state same-URL case).

## Manual verification checklist

- **Headline:** Kill Abbay. `"Hey Siri, play Harry Potter and the Goblet of Fire on Abbay"`. Expected: background-launches, plays. No YouTube Music mis-route.
- **Disambiguation:** Library has two Harry Potter books. Kill Abbay. `"Hey Siri, play Harry Potter on Abbay"`. Expected: Siri prompts to pick → user picks → plays.
- **Many-match cap:** Library has six books containing "audiobook". Kill Abbay. `"Hey Siri, play audiobook on Abbay"`. Expected: plays last-played tiebreak winner, no 6-way prompt.
- **Graceful launch + recovery:** Kill Abbay. Start a phone call. `"Hey Siri, play in Abbay"`. Expected: `"Audio temporarily unavailable."` NO crash. End the call. `"Hey Siri, play in Abbay"` again. Expected: this time succeeds — `Player.play` retries `setActive` and clears the flag.
- **Background-launch budget:** Invoke Siri 6+ times in close succession during an active phone call. Expected: each returns the unavailable dialog without iOS rate-limiting the extension (because the extension returns `.failureUnknownMediaType` from `handle`, no host-app launch consumed).
- **Donation learning:** Fresh device, install phase 2. Play a book manually 3+ times across separate sessions. Wait. `"Hey Siri, play Harry Potter"` (no `"on Abbay"`). Expected: eventually routes to Abbay.
- **Same-URL replay donation:** Play a book. Pause. Tap play. Donation fires on the resume too.
- **`ResumeAbbayIntent` warm-state donation:** While playing, `"Hey Siri, pause Abbay"`, then `"Hey Siri, continue audiobook in Abbay"`. Donation fires on the resume.
- **Delete staleness recovery:** Play book A; delete from library; immediately kill app; `"Hey Siri, play A on Abbay"`. Expected: `"Cannot find that audiobook..."` and snapshot refreshes.
- **Migration:** Upgrade install. Existing `LastPlayedStore` value in `.standard`. First main-app launch eager-seeds App Group; first Siri invocation reads same value.
- **Cold-background-launch with no MediaListView open:** Upgrade install, never open MediaListView, kill app, `"Hey Siri, play <book> on Abbay"`. Expected: AppDelegate eager-seed populates snapshot before extension reads (or, if extension reads first via App Group, gets empty → no-match dialog → user opens app → next invocation succeeds). Documented behavior.
- **Lazy bookmark population:** Legacy book without `bookmarkData`. Cold-start `"Hey Siri, play <book> on Abbay"`. First invocation: extension resolves via `URL(string:)` fallback. Main app plays, populates bookmarkData on the inout model, persists to Core Data, refreshes snapshot. Verify via `defaults read` on the App Group suite that the snapshot entry now has `bookmarkData` populated.
- **No regression:** Phase-1 phrases work cold-start.
- **CarPlay:** Connect device, repeat headline and pause/next phrases.

## Risks

- **`INPlayMediaIntent` mediaSearch reliability.** Forum thread [FB14872048](https://developer.apple.com/forums/thread/762196). Mitigation: short titles, manual checklist.
- **Donation rate vs Siri's learning model.** Apple does not publish thresholds. Phase 2 donates on every play; matches Spotify-class apps.
- **iOS background-launch budget for `INPlayMediaIntent` extensions.** Mitigation: extension returns `.failureUnknownMediaType` early when flag set, no host-app launch consumed.
- **App Group migration on existing installs.** Read-side fallback to `.standard` (main app only) + AppDelegate eager seed close the upgrade windows. Extension-only invocation before first main-app launch after upgrade: tiebreak degrades to library-index ordering (acceptable).
- **JSON snapshot freshness windows.** Writes on: library load, delete, import, lazy-bookmark-population, AppDelegate eager-seed, AppDelegate.handle nil-URL refresh. Remaining window: import-then-kill-before-`UserDefaults.set` (sub-millisecond, acceptable).
- **`bookmarkData` round-trip for legacy books.** First Siri invocation falls back to `URL(string:)`; main app's lazy migration in `Player.play` populates the bookmark and refreshes the snapshot; subsequent invocations use the bookmark path.
- **`Player.play(_:)` retry-setActive overhead.** `AVAudioSession.setActive(true)` when already active is a fast no-op per Apple's docs; one call per play is acceptable. If profiling shows otherwise, gate the retry on `LaunchStateFlag.isUnavailable()` (skip-retry when flag is false).
- **Extension build dependency on entitlements.** Misconfigured App Group surfaces as `UserDefaults(suiteName:) == nil` → `AppGroup.swift`'s `fatalError`. CI build smoke test exercises `LibrarySnapshotReader.read()` to surface misconfiguration before merge.
- **`com.apple.developer.siri` capability + App Store review.** Spotify, YouTube Music, Audible all ship this; no documented review issue.

## Open implementation questions (deferred to plan)

- **`FuzzyMatch.swift` source-sharing strategy** between main app and extension (target-membership vs duplicate). Pure code-org; both meet correctness. Tests on both sides lock identical vectors.

(Previously open: donation site, IntentDonor protocol, manual-vs-Siri donation payload differences, lazy-bookmark mutation site, snapshot refresh after migration, IntentDonor injection seam — all pinned above.)

## Phase 3 candidates (each with a falsifiable trigger)

- **Replace JSON snapshot with shared Core Data store in App Group OR `AbbayKit` framework extraction.** Trigger: maintenance pain from FuzzyMatch source-sharing OR a concrete need for in-extension playback OR shared state grows beyond the snapshot JSON shape.
- **`bookmarkData` round-trip in `LastPlayedStore.lastPlayedURL()` for full security-scoped URL durability.** Trigger: `ResumeAbbayIntent` cold-launch returns nil URL in production telemetry for users whose books survived `LoadAudioUseCase`.
- **iOS 18 AppIntents `AssistantSchemas` (`playMedia` / `playAudiobook`).** Trigger: Apple Intelligence rollout reaches a meaningful user share OR Siri's `INPlayMediaIntent` routing is deprecated.
- **`LocalizedStringResource` migration for all Siri dialog strings.** Trigger: first non-English locale launch of Abbay.
- **`AppIntentsExtension` target for phase-1 AppIntents.** Trigger: AppIntents background-execution latency becomes user-visible (e.g., `PauseAbbayIntent` lag > 1s in production telemetry).
- **CarPlay scene routing hook.** Trigger: phase-2 on-device CarPlay observation shows unwanted iPhone foregrounding during voice playback.
- **`INMediaItem` artwork in Siri lock-screen sheet.** Trigger: user-research signal showing blank-tile causes confusion in CarPlay or Siri lock-screen sheet, OR analytics on the Siri confirmation funnel shows drop-off.
