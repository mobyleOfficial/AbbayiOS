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
3. **`AppDelegate.fatalError` → graceful launch-state flag with retry-on-play recovery.** Replace the existing `AVAudioSession` `fatalError` pattern in `AbbayApp.swift` with a flag write. Both `setCategory` and `setActive` throws share one `do/catch` that sets `LaunchStateFlag.markUnavailable()`. All five existing AppIntents AND the new extension read the flag; when set, they speak `"Audio temporarily unavailable. Try again in a moment."`. **Recovery:** `Player.play(_:)` re-attempts `setCategory` + `setActive` at the top of every play; on success clears the flag, on throw returns early without playing.

Plus two UX polish items that the extension enables:

4. **Live disambiguation.** When `fuzzyMatch` returns multiple matches at the top score (see "Disambiguation rule" below), the extension returns `INPlayMediaMediaItemResolutionResult.disambiguation(with:)` instead of `.success(with:)`. Siri prompts the user to pick.
5. **`INPlayMediaIntent` donations.** After every successful play start — extension, AppIntent, or manual tap — donate `INPlayMediaIntent` via `INInteraction(intent:response:).donate()`. Feeds Siri's preferred-media-app learning. Identical payload across triggers (per WWDC19 session 207).

### Phase-2 fix coverage (against phase 1 limitations doc)

| # | Phase 1 limitation | Phase 2 fix |
|---|---|---|
| 1 | Cold-start `"play"` → wrong app | `INPlayMediaIntent` extension wins media-router priority |
| 2 | Cold-launch-during-call crash | `LaunchStateFlag` replaces `fatalError`; `Player.play` retries `setActive` |
| 3 | `PlayBookByNameIntent` is two-step | `INMediaSearch.mediaName` is arbitrary String; one-shot phrase works |
| 5 | AppShortcut entity-parameter restriction | Bypassed — extension is not AppIntents |
| 9 | No multi-match disambiguation | `INPlayMediaMediaItemResolutionResult.disambiguation(with:)` |

Limitations #4 (security-scoped URL round-trip), #6, #7, #8, #10, #11, #12 unchanged from phase 1. #4 partially addressed: `FileLoader.swift:51` already populates `AudioModel.bookmarkData` on import; legacy books migrated lazily on play (§bookmarkData population).

## Non-goals (deferred to phase 3 / later)

- **Full `AbbayKit` framework extraction.** Phase 2 uses a JSON snapshot in App Group `UserDefaults` and minimal source-sharing.
- **AppIntents `AssistantSchemas`** (`playMedia` / `playAudiobook`). Captured as a GitHub issue.
- **`AppIntentsExtension` target** for the phase-1 AppIntents.
- **Localization of all Siri dialog strings.**
- **`bookmarkData` round-trip in legacy `LastPlayedStore.lastPlayedURL()`.**
- **CarPlay-specific scene routing hooks.**
- **`"Abbay"` STT phonetic ambiguity remedy.**
- **`INMediaItem` artwork in Siri lock-screen sheet.**

Each phase-3 candidate has a falsifiable trigger condition listed in "Phase 3 candidates".

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
│   ├── Core/LastPlayedStore.swift         EDIT (migrate to App Group; preserve test seam)
│   ├── Core/Player/Player.swift           EDIT (retry-setActive, donation, lazy bookmark, snapshot refresh)
│   ├── Intents/AbbayIntents.swift         EDIT (LaunchStateFlag reads in perform())
│   ├── AbbayApp.swift                     EDIT (AppDelegate: re-order DI/session/seeds; replace fatalError; add handle())
│   └── View/MediaListView/
│       ├── MediaListView.swift            EDIT (pass closure to DocumentPickerView)
│       ├── MediaListViewModel.swift       EDIT (@MainActor; importAudio async)
│       └── DocumentPicker/DocumentPickerView.swift  EDIT (closure-based import handoff)
└── AbbayIntents (app-extension)           NEW TARGET
    ├── IntentHandler.swift
    ├── PlayMediaIntentHandler.swift
    ├── LibrarySnapshotReader.swift
    ├── FuzzyMatch.swift                   (source-membership-shared with Abbay target OR duplicated — plan decides)
    ├── PlayMediaIntent.intentdefinition   (custom no-match Response with input echo)
    ├── Info.plist
    └── AbbayIntents.entitlements          (App Group)
```

Note: `AppDelegate` is a class inside `Abbay/AbbayApp.swift` (not a separate `AppDelegate.swift` file). All phase-2 `AppDelegate` edits land in `AbbayApp.swift`.

### Cross-process state (App Group `group.com.edyuto.abbay`)

| Key | Type | Writer | Reader |
|---|---|---|---|
| `abbay.lastPlayedAudioURL` | String? | main app (`Player.play(_:)`; AppDelegate eager-seed) | main app, extension |
| `abbay.librarySnapshot.v1` | Data (JSON) | main app (`LibrarySnapshotWriter.write` on library load/delete/import; `LibrarySnapshotWriter.refresh` on lazy-bookmark + AppDelegate.handle nil-URL; AppDelegate eager-seed on launch) | extension (`LibrarySnapshotReader`) |
| `abbay.audioSessionUnavailable` | Bool | main app (AppDelegate catch; `Player.play` retry-clear or retry-mark) | main app (AppIntents, AppDelegate.handle), extension (resolveMediaItems + handle) |

Snapshot JSON shape:

```json
{
  "version": 1,
  "updatedAt": "2026-05-17T12:34:56Z",
  "audios": [
    { "title": "Harry Potter and the Goblet of Fire", "urlString": "file:///...", "bookmarkData": "<base64-or-omitted>" }
  ]
}
```

Extension is read-only. Main app is sole writer. `UserDefaults` writes are atomic; no locking needed.

### Capability + entitlement deltas

**Main app target:** App Group `group.com.edyuto.abbay`, `com.apple.developer.siri`, `NSSiriUsageDescription`: `"Abbay uses Siri to play your audiobooks and control playback when you say things like 'Play Harry Potter on Abbay' or 'Pause Abbay'."`

**Extension target (`AbbayIntents`):** App Group (same group); `NSExtension.NSExtensionAttributes.IntentsSupported = ["INPlayMediaIntent"]`; principal class `AbbayIntents.IntentHandler`; type `INExtension`. No background-modes.

**xcodegen `project.yml`:** new `targets.AbbayIntents` block (`type: app-extension`), embed in main app via `dependencies`; both targets get App Group + Siri entitlements. `IPHONEOS_DEPLOYMENT_TARGET` stays at `17.0`.

### Phase-1 AppIntents coexistence

All five phase-1 AppIntents ship unchanged in shape. Each `perform()` gains a top-of-method `LaunchStateFlag.isUnavailable()` gate that returns `"Audio temporarily unavailable..."` dialog when set. `PlayBookByNameIntent` is NOT retired — remains the Shortcuts-app path.

### Disambiguation rule

```
candidates = all entries with score equal to TOP score (strict equality)
if candidates.count == 1:    return .success(with: [candidate])
elif candidates.count <= 5:  return .disambiguation(with: candidates ordered by lastPlayedURL-first, then library index ASC)
else:                        return .success(with: [first per same tiebreak])  // > 5 → fall through
```

Cap of 5 is Apple's typical Siri-prompted list size. `>5` fallback preserves "always play something".

### `LaunchStateFlag` lifecycle

- **Set:** `AppDelegate.didFinishLaunching` catch branch (covers both `setCategory` and `setActive` throws).
- **Cleared:** at the TOP of every `Player.play(_:)`. Specifically: `Player.play` always re-attempts `try setCategory(.playback); try setActive(true)`. On success → `LaunchStateFlag.clear()` and continue. On throw → `LaunchStateFlag.markUnavailable()` and return early (no `player.play()`, no donation, no `LastPlayedStore.save`). `setActive(true)` when already active is a fast no-op per Apple's docs, so the retry is cheap; if profiling later shows otherwise the retry is trivially gateable on `isUnavailable()`.
- **Read by:** extension `resolveMediaItems` AND `handle`, main app `AppDelegate.application(_:handle:completionHandler:)`, all phase-1 AppIntent `perform()` methods.
- Expected lifetime: cleared on the first successful play after a launch-time flag set. No stale-forever failure mode.

### bookmarkData population

1. **Books imported via `FileLoader.load(url:)` (`FileLoader.swift:51`):** `AudioModel.bookmarkData` populated at import via `url.createBookmarkData()`. Snapshot writes carry it.
2. **Legacy books (pre-FileLoader-bookmark records in Core Data):** `bookmarkData` empty. Lazy migration: `Player.play(_:)` (BEFORE `updatePlayItem`) checks `model.bookmarkData == nil`; if true, attempts `url.createBookmarkData()` while holding security scope; if non-nil, mutates the `inout model` directly (so `updatePlayItem`, `IntentDonor.donatePlayMedia(model:)`, and `try? saveAudioUseCase.execute(model)` all see the populated copy), persists, then calls `librarySnapshotWriter.refresh()` so the next Siri invocation uses the bookmark path.

### Eager seeding at AppDelegate launch

AppDelegate `didFinishLaunching` ordering pinned (changes existing ordering — DI configure now precedes the audio session block):

```
1. DependencyContainer.configure()
2. do {
     try AVAudioSession.sharedInstance().setCategory(.playback)
     try AVAudioSession.sharedInstance().setActive(true)
     LaunchStateFlag.clear()
     eagerSeedIfNeeded()  // see below
   } catch {
     LaunchStateFlag.markUnavailable()
   }
3. return true
```

`eagerSeedIfNeeded`:

1. **LastPlayedStore seed** — if `AppGroup.defaults` has no value AND `UserDefaults.standard` has a value for `abbay.lastPlayedAudioURL`, copy `.standard` → AppGroup.
2. **LibrarySnapshot seed** — if `AppGroup.defaults` has no value for `abbay.librarySnapshot.v1`, run `LoadAllAudiosUseCase().execute()` and write via `LibrarySnapshotWriter.shared.write(audios:)`. **Risk:** on a cold background launch (Siri-triggered with no MediaListView), this synchronous Core Data fetch + JSON encode + UserDefaults write runs in the launch budget. For typical libraries (< 100 books) this is fast (< 50ms); for large libraries it may approach iOS's background-launch budget. Mitigation: keyed on "snapshot missing" — runs only on first-post-install/upgrade launches; subsequent launches are no-op. If on-device measurement shows latency issues, gate on `application.applicationState != .background` and defer to first foreground launch.

Both seeds are no-ops on subsequent launches.

## Data flow

### Cold-start `"Hey Siri, play Harry Potter and the Goblet of Fire on Abbay"`

1. Siri media-router → `AbbayIntents` extension.
2. `IntentHandler.handler(for:)` → `PlayMediaIntentHandler()`.
3. `resolveMediaItems(for:with:)`:
   - `LaunchStateFlag.isUnavailable()` → `completion([.unsupported(forReason: .unsupportedMediaType)])`; Siri then calls `handle` which returns `INPlayMediaIntentResponse(code: .failureUnknownMediaType)` with `"Audio temporarily unavailable..."` Response template. STOP.
   - `LibrarySnapshotReader.read()` empty → same shape with `"Add a book in Abbay first."` template.
   - `fuzzyMatch.matchAll(input:, audios:, lastPlayedURL:)` per disambiguation rule.
     - 0 → `.unsupported(...)` → `handle` returns no-match Response with input echo.
     - 1 → `.success(with: [INMediaItem(identifier: urlString, title:, type: .audioBook, artwork: nil)])`.
     - 2–5 → `.disambiguation(with: items)`. Siri prompts; user picks; Siri re-invokes resolve with chosen item populated.
     - >5 → fall through to single-best per tiebreak.
4. `handle(intent:completion:)` returns `.handleInApp` (audio playback per Apple docs). System background-launches host app.
5. `AppDelegate.didFinishLaunching` runs per pinned order above (DI → session → flag clear → eager seeds).
6. iOS calls `application(_:handle:completionHandler:)`:
   - `LaunchStateFlag.isUnavailable()` → completion with `.failureUnknownMediaType`.
   - Else: resolve `intent.mediaItems.first?.identifier` → URL (prefer snapshot's `bookmarkData` lookup, fall back to `URL(string:)`).
   - `LoadAudioUseCase.execute(url:)` → nil → completion with `.failureUnknownMediaType`; if URL matches `LastPlayedStore.lastPlayedURL()` clear it; call `librarySnapshotWriter.refresh()` to evict stale entry.
   - `player.play(&model)` (internally: retry setActive, lazy bookmark migration + snapshot refresh if needed, save LastPlayedStore, donate). Completion `.success`.

### Warm-state, manual tap, AppIntent paths

All converge on `Player.play(_:)`. Same donation hook; identical payload.

### Player.play(_:) sequence (pinned)

```swift
func play(_ model: inout AudioModel) {
    guard let url = model.url else { return }

    // Step 1 — defense-in-depth audio session recovery
    do {
        try AVAudioSession.sharedInstance().setCategory(.playback)
        try AVAudioSession.sharedInstance().setActive(true)
        LaunchStateFlag.clear()
    } catch {
        LaunchStateFlag.markUnavailable()
        return  // do not play, do not donate
    }

    // Step 2 — lazy bookmark population on the inout model
    if model.bookmarkData == nil {
        if url.startAccessingSecurityScopedResource() {
            model.bookmarkData = url.createBookmarkData()
            url.stopAccessingSecurityScopedResource()
            try? saveAudioUseCase.execute(model)
            librarySnapshotWriter.refresh()  // bounded path: legacy-book first-play only
        }
    }

    // Step 3 — existing item-switch path
    if url != self.url {
        saveTime()
        updatePlayItem(model)  // sees the populated bookmarkData via copy
        seek(model.currentTime)
    }

    // Step 4 — playback + post-play side effects (unconditional on URL-change)
    player.play()
    LastPlayedStore.save(url: url)
    intentDonor.donatePlayMedia(model: model)
}
```

`updatePlayItem(_ item: AudioModel)` is simplified — its current `LastPlayedStore.save(url: url)` (at `Player.swift:172`) is REMOVED (moved to Step 4). No bookmark mutation, no donation inside `updatePlayItem`.

**Layering note:** snapshot refresh is owned by `LibrarySnapshotWriter` (the `refresh()` method internally runs `LoadAllAudiosUseCase().execute()` and writes), so `Player` only sees the writer. `Player.init` does NOT take `LoadAllAudiosUseCase` — keeps Player's data-layer surface narrow.

**Manual-tap UX trade-off:** post-phase-2, a manual play tap during an active phone call (audio session unavailable) silently no-ops at Step 1's catch. Pre-phase-2 the app would have crashed at launch before the user could even reach the play button. This is an accepted trade-off: silent no-op is strictly better than crash, but produces no UI feedback. Phase-3 candidate: surface a toast / error subject on Player when Step 1 catches.

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

**`PlayMediaIntentHandler.swift`** — `~120 lines`. Per §Data flow §step 3-4.

**`LibrarySnapshotReader.swift`** — `~40 lines`. Decodes from App Group; returns empty on missing/malformed.

**`FuzzyMatch.swift`** — pure helper. `matchAll(...)` returns all top-score entries (new); `fuzzyMatch(...)` keeps the existing single-result signature.

**`PlayMediaIntent.intentdefinition`** — custom Response templates: `"Audio temporarily unavailable..."`, `"No audiobook matches '<input>'."` (parameter-interpolated), `"Add a book in Abbay first."`.

### Main-app new files

**`Abbay/Core/AppGroup.swift`**:
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

This `fatalError` is intentional (build-time misconfig surface). Different from the runtime-condition `fatalError` being removed from `AbbayApp.swift`.

**`Abbay/Core/LibrarySnapshotWriter.swift`** — `~70 lines`:
```swift
protocol LibrarySnapshotWriterProtocol {
    func write(audios: [AudioModel])  // explicit list — used by view model
    func refresh()                     // self-reads via LoadAllAudiosUseCase — used by Player + AppDelegate.handle
}

final class LibrarySnapshotWriter: LibrarySnapshotWriterProtocol {
    static let shared: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter()
    private let loadAllAudios: LoadAllAudiosUseCaseProtocol
    init(loadAllAudios: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase()) { ... }
    func write(audios: [AudioModel])
    func refresh()  // calls loadAllAudios.execute() then self.write
}
```

The `refresh()` method owns the data-layer call so callers (Player, AppDelegate) don't need `LoadAllAudios` injection.

**`Abbay/Core/LaunchStateFlag.swift`**:
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

**`Abbay/Core/LastPlayedStore.swift`** — current file has `static var defaults: UserDefaults = .standard` as an explicit test seam (line 17). Migration preserves the test seam:

```swift
// Was: static var defaults: UserDefaults = .standard
// Now: static var defaults: UserDefaults = AppGroup.defaults  (still `var` for test injectability)

// On read:
//   if defaults has no value AND UserDefaults.standard has → return .standard value (main-app only; extension's .standard is a different domain)
//   else return defaults value (may be nil)
// On write (main app only):
//   if defaults has no value AND .standard has → copy .standard → defaults (one-shot seed)
//   ALWAYS write new value to defaults
```

Tests assign `LastPlayedStore.defaults = UserDefaults(suiteName: "test-XYZ")` and `UserDefaults.standard` shadow values to exercise migration ordering.

**`Abbay/Core/Player/Player.swift`** — per §Player.play(_:) sequence above. New init signature (three new injectable dependencies, NOT four; `loadAllAudios` lives inside `LibrarySnapshotWriter`):

```swift
init(
    saveAudioUseCase: SaveAudioUseCaseProtocol = SaveAudioUseCase(),
    intentDonor: IntentDonorProtocol = IntentDonor.shared,
    librarySnapshotWriter: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter.shared
)
```

Existing call sites compile unchanged (sensible defaults). Tests inject mocks for `intentDonor` and `librarySnapshotWriter`.

**`Abbay/AbbayApp.swift`** — `AppDelegate` lives here. Edits:
- **Re-order** `didFinishLaunching`: `DependencyContainer.configure()` runs FIRST (before the audio session block). Currently in source it's reversed (audio session then DI configure at line 23). This re-ordering is required because the eager-seed step calls into the data layer, and we want a single canonical "DI first" lifecycle for all future expansion.
- Replace `fatalError(...)` in the catch with `LaunchStateFlag.markUnavailable()` (no re-raise, no crash).
- Insert `LaunchStateFlag.clear()` AND `eagerSeedIfNeeded()` at the END of the success branch.
- Implement `func application(_ app: UIApplication, handle intent: INIntent, completionHandler: @escaping (INIntentResponse) -> Void)` per §Data flow §step 6.

**`Abbay/Intents/AbbayIntents.swift`** — top of each `perform()`:
```swift
guard !LaunchStateFlag.isUnavailable() else {
    return .result(dialog: IntentDialog(Self.audioUnavailableDialog))
}
```
`static let audioUnavailableDialog = "Audio temporarily unavailable. Try again in a moment."`

**`Abbay/View/MediaListView/MediaListViewModel.swift`** — annotate `@MainActor` (class-level). Add:
```swift
@MainActor
func importAudio(from urls: [URL]) async {
    let newFiles = await fileLoader.load(urls: urls)
    for file in newFiles where !audioList.contains(where: { $0.url == file.url }) {
        audioList.append(file)
    }
    LibrarySnapshotWriter.shared.write(audios: audioList)
    AbbayAppShortcuts.updateAppShortcutParameters()
}
```

`@MainActor` annotation eliminates the SwiftUI "publishing from background" warning when `audioList` mutates after the `await`. Existing methods that mutate `audioList` are already implicitly main-actor due to UI binding; the annotation makes the contract explicit.

After `loadAllAudios` and `deleteAudio` (existing methods), call `LibrarySnapshotWriter.shared.write(audios: audioList)` alongside existing shortcut updates.

**`Abbay/View/DocumentPicker/DocumentPickerView.swift`** — refactor to a closure-based import handoff. Removes the `@Binding selectedFiles` AND the `fileLoader` (both now owned by the view model). New signature:

```swift
struct DocumentPickerView: UIViewControllerRepresentable {
    var onImport: ([URL]) async -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImport: onImport) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onImport: ([URL]) async -> Void
        init(onImport: @escaping ([URL]) async -> Void) { self.onImport = onImport }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            Task { await onImport(urls) }
        }
    }
}

struct DocumentPickerView_Previews: PreviewProvider {
    static var previews: some View { DocumentPickerView(onImport: { _ in }) }
}
```

Closure form keeps `DocumentPickerView` ignorant of `MediaListViewModel` (trivial preview, cleaner unit tests). The Task body inherits the main actor from the UIKit delegate callback caller; combined with `@MainActor` on `MediaListViewModel.importAudio`, all `audioList` mutations run on the main thread.

**`Abbay/View/MediaListView/MediaListView.swift`** — call site becomes:
```swift
DocumentPickerView(onImport: { urls in await model.importAudio(from: urls) })
```

**`project.yml`** — add the `AbbayIntents` target, App Group entitlement on both, Siri entitlement + `NSSiriUsageDescription` on main app.

## Tests

### New target `AbbayIntentsTests`

- `PlayMediaIntentHandlerTests.resolveMediaItems_singleMatch_returnsSuccess`
- `PlayMediaIntentHandlerTests.resolveMediaItems_twoToFiveMatchesAtTopScore_returnsDisambiguation`
- `PlayMediaIntentHandlerTests.resolveMediaItems_moreThanFiveMatchesAtTopScore_returnsSingleBest`
- `PlayMediaIntentHandlerTests.resolveMediaItems_noMatch_returnsUnsupported_thenHandleReturnsFailureWithNoMatchDialog`
- `PlayMediaIntentHandlerTests.resolveMediaItems_emptyLibrary_returnsUnsupported_thenHandleReturnsFailureWithEmptyLibraryDialog`
- `PlayMediaIntentHandlerTests.resolveMediaItems_audioSessionUnavailableFlag_returnsUnsupported_thenHandleReturnsFailureWithUnavailableDialog`
- `PlayMediaIntentHandlerTests.handle_singleMatchPath_returnsHandleInApp`
- `ExtensionFuzzyMatchTests` — same vectors as phase-1's `FuzzyMatchTests` plus multi-match (`matchAll`) cases.
- `LibrarySnapshotReaderTests.read_validJSON_returnsEntries`
- `LibrarySnapshotReaderTests.read_missingValue_returnsEmpty`
- `LibrarySnapshotReaderTests.read_malformedJSON_returnsEmpty`

### Extending `AbbayTests` (main app)

- `AppDelegateTests.didFinishLaunching_orderingDIBeforeAudioSession`
- `AppDelegateTests.audioSessionSetActiveThrow_setsFlag_doesNotCrash`
- `AppDelegateTests.audioSessionSetCategoryThrow_setsFlag_doesNotCrash`
- `AppDelegateTests.didFinishLaunching_emptySnapshot_eagerSeedsFromLoadAllAudios`
- `AppDelegateTests.didFinishLaunching_populatedSnapshot_skipsEagerSeed`
- `AppDelegateTests.didFinishLaunching_lastPlayedInStandardOnly_seedsAppGroup`
- `AppDelegateTests.handlePlayMediaIntent_callsPlayer`
- `AppDelegateTests.handlePlayMediaIntent_audioUnavailable_returnsFailure_doesNotCallPlayer`
- `AppDelegateTests.handlePlayMediaIntent_loadAudioReturnsNil_returnsFailure_clearsLastPlayedIfMatched_refreshesSnapshot`
- `LibrarySnapshotWriterTests.write_decodableByExtensionReader_roundTrip`
- `LibrarySnapshotWriterTests.write_afterDelete_removesEntry`
- `LibrarySnapshotWriterTests.write_excludesBookmarkDataWhenModelEmpty`
- `LibrarySnapshotWriterTests.write_includesBookmarkDataWhenModelPopulated`
- `LibrarySnapshotWriterTests.refresh_callsLoadAllAudios_thenWrites`
- `LastPlayedStoreTests.migration_standardToAppGroup_seedThenWrite_zeroLoss`
- `LastPlayedStoreTests.read_preservesTestInjectionSeam`
- `LaunchStateFlagTests.markUnavailable_thenClear_roundTrip`
- `LaunchStateFlagTests.isUnavailable_defaultsFalse`
- `PlayerTests.play_setActiveSucceedsWhenFlagWasFalse_keepsFlagFalse_playsAndDonates`
- `PlayerTests.play_setActiveSucceedsWhenFlagWasTrue_clearsFlag_playsAndDonates_recoveryHappyPath`
- `PlayerTests.play_setActiveThrows_setsFlag_doesNotCallAVPlayerPlay_doesNotDonate`
- `PlayerTests.play_sameURLReplay_donatesEachTime`
- `PlayerTests.play_firstPlayOfBookWithoutBookmark_populatesBookmarkDataOnInoutModel_callsSnapshotRefresh`
- `PlayerTests.play_firstPlayOfBookWithBookmark_doesNotRePopulate_doesNotCallSnapshotRefresh`
- `MediaListViewModelTests.importAudio_appendsNonDuplicates_writesSnapshot_updatesShortcuts` (annotated `@MainActor`)
- Existing `IntentTests` extended: each phase-1 intent's `perform()` gets a sibling case asserting flag=true → unavailable dialog, no `Player` call.
- Existing `IntentTests` extended: `ResumeAbbayIntent`-driven `Player.play(_:)` triggers `IntentDonor.donatePlayMedia` even when `updatePlayItem` is skipped (warm-state same-URL).

## Manual verification checklist

- **Headline:** Kill Abbay. `"Hey Siri, play Harry Potter and the Goblet of Fire on Abbay"`. Expected: background-launches, plays.
- **Disambiguation:** Library has two Harry Potter books. Kill Abbay. `"Hey Siri, play Harry Potter on Abbay"`. Expected: Siri prompts, user picks, plays.
- **Many-match cap:** Library has six books with "audiobook". Kill Abbay. `"Hey Siri, play audiobook on Abbay"`. Expected: plays last-played tiebreak; no 6-way prompt.
- **Graceful launch + recovery:** Kill Abbay. Start a phone call. `"Hey Siri, play in Abbay"`. Expected: `"Audio temporarily unavailable."` NO crash. End the call. Same phrase. Expected: succeeds — `Player.play` retried `setActive` and cleared the flag.
- **Background-launch budget:** Invoke Siri 6+ times during an active call. Expected: each returns the unavailable dialog without iOS rate-limiting (extension returns `.failureUnknownMediaType` from `handle`, no host-app launch consumed).
- **Donation learning:** Fresh device, install phase 2. Play 3+ times across sessions. `"Hey Siri, play Harry Potter"` (no `"on Abbay"`). Expected: eventually routes to Abbay.
- **Same-URL replay donation:** Play. Pause. Tap play. Donation fires on the resume too.
- **`ResumeAbbayIntent` warm-state donation:** While playing, `"pause Abbay"` then `"continue audiobook in Abbay"`. Donation fires.
- **Delete staleness recovery:** Play A. Delete A. Kill app. `"play A on Abbay"`. Expected: `"Cannot find that audiobook..."` AND snapshot refreshes (verify via App Group `defaults read`).
- **Migration:** Upgrade install with existing `LastPlayedStore.standard` value. First main-app launch eager-seeds App Group; extension reads correct value.
- **Cold-background-launch with no MediaListView:** Upgrade install, never open MediaListView, kill app, `"play <book> on Abbay"`. Expected: AppDelegate eager-seed populates snapshot; Siri invocation succeeds. If extension reads before AppDelegate seed completes (race), expect no-match dialog → user opens app → next invocation succeeds.
- **Lazy bookmark population:** Legacy book without `bookmarkData`. Cold-start Siri play. Verify snapshot updates with `bookmarkData` populated (`defaults read` on suite).
- **Manual tap during call:** Phone call active. App alive. Manually tap play in UI. Expected: silent no-op (no crash, no UI feedback — accepted phase-2 trade-off; phase-3 toast surface).
- **No regression:** Phase-1 phrases work cold-start.
- **CarPlay:** Connect device, repeat headline and pause/next phrases.

## Risks

- **`INPlayMediaIntent` mediaSearch reliability.** Forum thread [FB14872048](https://developer.apple.com/forums/thread/762196). Mitigation: short titles, manual checklist.
- **Donation rate vs Siri's learning model.** Apple doesn't publish thresholds. Phase 2 donates on every play; matches Spotify-class apps.
- **iOS background-launch budget.** Extension returns `.failureUnknownMediaType` early when flag set, no host-app launch consumed.
- **App Group migration on existing installs.** Read-side fallback to `.standard` (main app only) + AppDelegate eager seed close the upgrade windows. Extension-only invocation before first main-app launch: tiebreak degrades to library-index ordering (acceptable).
- **JSON snapshot freshness.** Writes on library load + delete + import + lazy-bookmark + AppDelegate eager-seed + AppDelegate.handle nil-URL refresh. Remaining window: import-then-kill-before-`UserDefaults.set` (sub-millisecond).
- **`bookmarkData` for legacy books.** First Siri invocation falls back to `URL(string:)`; main app's lazy migration populates the bookmark and refreshes snapshot.
- **Eager-seed Core Data read on cold-background-launch.** Synchronous Core Data fetch + JSON encode + UserDefaults write on launch when snapshot missing. Bounded to first-post-install/upgrade launches. Large libraries (>100 books) may approach iOS background-launch budget. Mitigation if observed: gate seed on `application.applicationState != .background` and defer to first foreground launch (accepts one extra extension invocation may see empty snapshot — already documented behavior).
- **`Player.play` retry-setActive overhead.** `AVAudioSession.setActive(true)` when already active is a fast no-op per Apple docs. If profiling shows otherwise, gate retry on `LaunchStateFlag.isUnavailable()`.
- **`librarySnapshotWriter.refresh()` inside `Player.play` lazy-migration branch.** Synchronous Core Data fetch on the play hot path, bounded to first-play of legacy books (no bookmark). Mitigation if observed: defer via `Task { ... }` after `player.play()`.
- **Manual play tap during audio session unavailable.** Silent no-op (no UI feedback). Pre-phase-2 the app would have crashed at launch before reach. Accepted trade-off; phase-3 candidate adds UI signal.
- **Extension build dependency on entitlements.** Misconfigured App Group → `AppGroup.swift` `fatalError`. CI smoke test exercises `LibrarySnapshotReader.read()`.
- **`com.apple.developer.siri` capability + App Store review.** Spotify-class apps all ship it; no documented review issue.

## Open implementation questions (deferred to plan)

- **`FuzzyMatch.swift` source-sharing strategy** between main app and extension (target-membership vs duplicate). Pure code-org; both meet correctness.

## Phase 3 candidates (each with a falsifiable trigger)

- **Shared Core Data / `AbbayKit` framework.** Trigger: source-sharing maintenance pain, or in-extension playback need.
- **`bookmarkData` round-trip in `LastPlayedStore.lastPlayedURL()`.** Trigger: `ResumeAbbayIntent` cold-launch returns nil URL in production telemetry.
- **iOS 18 AppIntents `AssistantSchemas`.** Trigger: Apple Intelligence reaches meaningful user share, or Siri `INPlayMediaIntent` deprecation.
- **`LocalizedStringResource` migration.** Trigger: first non-English locale launch.
- **`AppIntentsExtension` target.** Trigger: AppIntents background-execution latency becomes user-visible.
- **CarPlay scene routing hook.** Trigger: on-device CarPlay observation shows unwanted iPhone foregrounding.
- **`INMediaItem` artwork in Siri lock-screen sheet.** Trigger: blank-tile confusion in user research, or Siri funnel drop-off.
- **Manual-tap-during-unavailable UI signal.** Trigger: user reports of "play button does nothing" after first phase-2 production install.
