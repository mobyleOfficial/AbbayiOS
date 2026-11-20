# Sleep timer and back to where you fell asleep: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** an Apple Books-style sleep timer on the player (PR 1), then a saved per-book prompt that
returns to where the listener fell asleep (PR 2).

**Architecture:** a `@MainActor @Observable SleepTimer` beside `PlaybackCenter`, built once in
`DependencyContainer`. `PlaybackCenter` forwards playback events to it through a small observer
protocol; it drives a fade through a new non-saving `Player` fade level and pauses the player. Time
comes from an injected monotonic scheduler, so unit tests advance time by hand. PR 2 adds a
`SleepReturnCenter` that listens to the timer's stop events and to playback, and keeps one spot
per book in `AppSettings`.

**Tech stack:** Swift, SwiftUI (iOS 17 floor), Observation, Combine, AVFoundation, XCTest/XCUITest.

**Spec:** `docs/superpowers/specs/2026-11-11-sleep-timer-design.md` (read it; this plan argues
from it).

## Global constraints

- Deployment target stays iOS 17.0; gate newer APIs with `@available`.
- Every user-visible string goes in `Abbay/Resources/Localizable/Localizable.xcstrings` with `en`
  and `pt-BR`, plus a case in `Localizable.swift`.
- New accessibility ids go in `Abbay/Core/AccessibilityID.swift`, launch arguments in
  `Abbay/Core/LaunchArgument.swift` (and its `all` list); behaviour for them in
  `Abbay/DebugSupport/DebugOverrides.swift`, `#if DEBUG`.
- Never change the system volume; the fade must never be saved as the listener's volume.
- Don't touch the LibriVox download layer's `@escaping` closures.
- SwiftLint strict passes. Run tests on your own simulator with `-parallel-testing-enabled NO`.
- After adding files, `xcodegen generate` (the project is generated).
- No AI attribution in commits or PR bodies.

## Xcode skills to use (xcode-integration plugin)

- **Tasks 5 and 10 (SwiftUI):** consult `xcode-integration:swiftui-specialist` before writing the
  pill and the prompt (`TimelineView`, `Menu`, `@Observable` invalidation, localization).
- **Strings:** add them through the `StringCatalogEdit` tool (`xcode-integration:translation`
  for the pt-BR values), not by hand-editing the JSON.
- **After Tasks 5 and 10:** run `xcode-integration:accessibility-voiceover-specialist` and
  `xcode-integration:accessibility-dynamic-type-specialist` on `SleepTimerPill.swift` and
  `SleepReturnPromptView.swift`; fix what they find or file it.
- **Tasks 6 and 11 (live check):** a subagent with `xcode-integration:device-interaction`
  drives the app (`DeviceInteractionInstallAndRun` with `commandLineArguments`
  `["$(inherited)", "-seedLibrary", "-resetSettings", "-sleepTimerSeconds", "8"]`), taking the
  screenshots that become the PR's evidence. `xcode-integration:app-resizability` informs the iPad
  split and Duo check of the pill row.
- The gate still runs through `xcodebuild` on our own simulator (`CLAUDE.md`), not Xcode's
  `RunAllTests`, so it doesn't share a destination with anyone.

## Review focus

1. **A phone call or Siri interrupts during the fade:** the pause must still land and the volume
   must come back to the listener's level, not stay at the faded gain (Task 2 test
   `test_pauseDuringFade_finishesTheTimer_andRestoresTheLevel`).
2. **End of chapter on a LibriVox book overshoots into the next file:** the ramp must hold the gain
   at 0 until the pause, and the target must not re-aim at the next chapter once the fade has
   begun (Task 3 test `test_endOfChapter_targetLocksOnceTheFadeBegins`).
3. **The speed changes while an end-of-chapter timer runs:** the wall-clock deadline must follow
   (Task 3 test `test_endOfChapter_followsASpeedChange`).
4. **The book is deleted while a timer runs:** the timer goes Off and the gain is restored (Task 2
   test `test_unload_cancels`).
5. **Relaunch with a spot saved for a book that is not loaded:** the prompt shows on that book's
   player, and *Back* moves the book's saved position without needing it loaded (Task 9 test
   `test_goBack_onAnUnloadedBook_savesThePosition`).

---

# PR 1: sleep timer (branch `feat/sleep-timer`)

### Task 1: Player fade level and book-end event

**Files:**
- Modify: `Abbay/Core/Player/Player.swift` (protocol, `// MARK: - Volume`, `bookDidEnd()`)
- Modify: `AbbayTests/Mocks/MockPlayer.swift`
- Test: `AbbayTests/PlayerFadeTests.swift` (new; reuse `PlayerVolumeTests.makePlayer` shape)

**Interfaces — produces:**
- `PlayerProtocol.fadeLevel: Double { get }`: 1 when not fading.
- `PlayerProtocol.setFadeLevel(_ level: Double)`: clamps to 0…1, multiplies the applied gain, never
  writes `volumes.volume`.
- `PlayerProtocol.bookEndPublisher: AnyPublisher<Void, Never>`: fires on main from `bookDidEnd()`
  (single-file and multi-file ends both call it).
- Protocol-extension defaults: `fadeLevel` 1, `setFadeLevel` no-op, `bookEndPublisher` `Empty`.
- `Player.setVolume(_:)` resets `fadeLevel` to 1 (the listener's change is heard at once; the timer
  notices `fadeLevel` differs from what it set and stops ramping).
- `MockPlayer`: stored `fadeLevel` (default 1), `fadeLevels: [Double]` recording,
  `emitBookEnd()`, `playbackRate` settable stub, `volume`/`setVolume` that resets `fadeLevel` to 1.

- [ ] **Step 1: Write failing tests** in `PlayerFadeTests`:
  - `test_fadeLevel_scalesTheGain_withoutSavingTheVolume`: `settings.volume = 0.6`, player built;
    `setFadeLevel(0.5)` → `requestedVolume ≈ 0.3`, `settings.volume == 0.6`, `fadeLevel == 0.5`.
  - `test_fadeLevel_scalesTheBoost`: volume 1.6 → `setFadeLevel(0.5)` → `requestedVolume * boostGain`
    product halves (compare to before), `settings.volume == 1.6`.
  - `test_setVolume_resetsTheFade`: `setFadeLevel(0.2)`; `setVolume(0.8)` → `fadeLevel == 1`,
    `requestedVolume ≈ 0.8`.
  - `test_fadeLevel_isClamped`: `setFadeLevel(-1)` → 0; `setFadeLevel(2)` → 1.
  - `test_bookDidEnd_publishes`: subscribe to `bookEndPublisher`, call `bookDidEnd()`, expect one
    value.
- [ ] **Step 2:** Run `xcodebuild test … -only-testing:AbbayTests/PlayerFadeTests`; expect compile
  failure.
- [ ] **Step 3: Implement.** `apply(volume:)` becomes `apply(volume: Double, fade: Double)`: the
  player gain is `BookVolume.playerVolume(volume) * fade` and the boost gain is scaled so the total
  gain is multiplied by `fade` (at `fade == 0` both are silent).
- [ ] **Step 4:** Re-run; expect PASS. Also run `PlayerVolumeTests`, `BookVolumeTests`: PASS.
- [ ] **Step 5: Commit** `feat(player): a fade level under Abbay's volume, and a book-end event (#332)`.

### Task 2: SleepTimer, durations

**Files:**
- Create: `Abbay/Core/Playback/SleepTimer.swift`, `Abbay/Core/Playback/SleepTimerScheduling.swift`
- Modify: `Abbay/Core/Playback/PlaybackCenter.swift`
- Test: `AbbayTests/SleepTimerTests.swift`, `AbbayTests/Mocks/ManualSleepTimerScheduler.swift`

**Interfaces — produces:**
```swift
enum SleepTimerChoice: Hashable {
    case duration(TimeInterval)   // seconds
    case endOfChapter
    static let durations: [TimeInterval] = [300, 600, 900, 1800, 2700, 3600]
}
struct SleepTimerStop: Equatable { let bookURL: URL; let stoppedAt: Double }  // book time T
enum SleepTimerEvent: Equatable { case set(bookURL: URL?); case stopped(SleepTimerStop) }

@MainActor protocol SleepTimerScheduling {
    var now: TimeInterval { get }                                   // monotonic seconds
    func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> AnyCancellable
}
struct TaskSleepTimerScheduler: SleepTimerScheduling   // ContinuousClock + Task.sleep

@MainActor protocol PlaybackEventObserving: AnyObject {
    func playingChanged(_ isPlaying: Bool)
    func timeChanged(bookTime: Double)
    func bookEnded()
    func bookUnloaded()
    func chaptersChanged()
}   // extension gives empty defaults

@MainActor @Observable final class SleepTimer: PlaybackEventObserving {
    init(player: PlayerProtocol,
         loadedBook: @escaping @MainActor () -> AudioModel?,
         scheduler: SleepTimerScheduling = TaskSleepTimerScheduler(),
         fadeDuration: TimeInterval = 5,
         firstDurationOverride: TimeInterval? = nil)   // -sleepTimerSeconds: the 5-minute choice lasts this long
    private(set) var choice: SleepTimerChoice?        // nil = Off
    func set(_ choice: SleepTimerChoice?)             // nil cancels; publishes .set(bookURL:)
    func remaining() -> TimeInterval?                 // duration only; nil when Off or end of chapter
    func choices(for book: AudioModel?) -> [SleepTimerChoice]   // endOfChapter first, only if book has chapters
    var events: AnyPublisher<SleepTimerEvent, Never>
}
```
- `PlaybackCenter.addObserver(_ observer: PlaybackEventObserving)` (held weakly, called on main):
  `playingChanged` from the `isPlayingPublisher` sink, `timeChanged` after each applied tick,
  `bookEnded` from `player.bookEndPublisher`, `bookUnloaded` from `unload()`, `chaptersChanged`
  from `replaceChapters`.

**Behaviour (duration):** counts only while playing (`playingChanged`), using
`scheduler.now` deltas, never tick counts. At `fadeDuration` before the end it ramps
`player.setFadeLevel` down in 0.25 s steps to 0; before each step, if `player.fadeLevel` isn't
what it last set, the listener changed the volume: stop ramping and leave their level. At the end:
mark Off first, then `player.pause()`, `player.setFadeLevel(1)`, publish
`.stopped(bookURL, stoppedAt: player.currentTime)`. A pause during the fade finishes the same way
(Off, restore, publish). `bookEnded` while set: Off, restore, publish `.stopped`. `bookUnloaded`:
Off, restore, no event. `set(nil)` during a fade restores the level.

- [ ] **Step 1: Write `ManualSleepTimerScheduler`** (`now` settable, `advance(by:)` runs due work
  in order, including work scheduled while advancing).
- [ ] **Step 2: Write failing tests** (`MockPlayer`, a book with `url`, `fadeDuration: 5`):
  - `test_duration_countsOnlyWhilePlaying`: set `.duration(600)`, playing 100 s, paused 1000 s,
    playing 100 s → `remaining() == 400`.
  - `test_pauseHolds_playResumes`: paused mid-run, `advance(3600)` → no `pause()` call, still set.
  - `test_duration_fadesThenPauses`: set `.duration(60)`, playing; `advance(54)` → `fadeLevels`
    empty; `advance(6)` → `fadeLevels` strictly decreasing ending at 0, then `pauseCallCount == 1`,
    `fadeLevel == 1`, `choice == nil`, one `.stopped(SleepTimerStop(bookURL:, stoppedAt:))`.
  - `test_volumeChangeDuringFade_stopsTheRamp_butStillPauses`: mid-fade `player.setVolume(0.7)`
    → no further `fadeLevels` after it; pause still at the end.
  - `test_pauseDuringFade_finishesTheTimer_andRestoresTheLevel`: mid-fade `playingChanged(false)`
    → `choice == nil`, `fadeLevel == 1`, one `.stopped`.
  - `test_off_cancels`, `test_replacingTheChoice_restartsTheCount` (set 600, play 100, set 300 →
    `remaining() == 300`), `test_set_publishesSet`.
  - `test_unload_cancels`: mid-fade `bookUnloaded()` → Off, `fadeLevel == 1`, no `.stopped`.
  - `test_bookEnd_whileSet_stops`: `bookEnded()` → Off, `.stopped` published.
  - `test_choices_offerEndOfChapterOnlyWithChapters`; `test_firstDurationOverride_shortensFiveMinutes`
    (override 8 → `.duration(300)` set → `remaining() == 8`).
- [ ] **Step 3:** Run `-only-testing:AbbayTests/SleepTimerTests`; expect FAIL.
- [ ] **Step 4: Implement** `SleepTimer` and the `PlaybackCenter` observer hook.
- [ ] **Step 5:** Run `SleepTimerTests` and `PlaybackCenterTests`; expect PASS. Add to
  `PlaybackCenterTests`: `test_observer_receivesPlayingTicksEndAndUnload` with a recording observer.
- [ ] **Step 6: Commit** `feat(playback): a sleep timer that counts listening time and fades out (#332)`.

### Task 3: SleepTimer, end of chapter

**Files:** Modify `Abbay/Core/Playback/SleepTimer.swift`; Test `AbbayTests/SleepTimerTests.swift`.

**Behaviour:** while playing, the end is the `endTime` of the chapter holding the current book
time (`loadedBook()?.currentChapter(for:)`), or the book's `duration` with no chapters. Wall time
left = `(end − bookTime) / player.playbackRate`. Re-aim on `playingChanged(true)`, every
`timeChanged`, and `chaptersChanged`, until the fade begins; from then the end is fixed and ticks
are ignored, the gain stays 0 until the pause.

- [ ] **Step 1: Write failing tests** (book with chapters 0–100, 100–250, 250–400):
  - `test_endOfChapter_pausesAtTheChapterEnd`: set at bookTime 30, playing → pause when the
    scheduler reaches 70 s (±0.25).
  - `test_endOfChapter_followsASpeedChange`: at bookTime 50 set `playbackRate = 2`, `timeChanged(50)`
    → pause 25 s later.
  - `test_endOfChapter_reaimsAfterAChapterJump`: `timeChanged(120)` before the fade → end is 250.
  - `test_endOfChapter_targetLocksOnceTheFadeBegins`: in the fade, `timeChanged(101)` → still
    pauses at the original deadline, `fadeLevels` never rise.
  - `test_endOfChapter_withoutChapters_meansTheBookEnd`, `test_endOfChapter_reaimsWhenChaptersAreReplaced`.
  - `test_endOfChapter_inTheLastChapter_bookEndStops` (`bookEnded()` → `.stopped`).
- [ ] **Step 2:** Run; FAIL. **Step 3:** Implement. **Step 4:** Run; PASS.
- [ ] **Step 5: Commit** `feat(playback): the sleep timer can stop at the end of the chapter (#332)`.

### Task 4: Wiring and the short-timer launch argument

**Files:**
- Modify: `Abbay/Core/DI/DependencyContainer.swift` (`let sleepTimer: SleepTimer`, built on main
  after `playback`, `playback.addObserver(sleepTimer)`), `AbbayTests/Mocks/MockDependencyContainer.swift`
- Modify: `Abbay/Core/LaunchArgument.swift`: `static let sleepTimerSeconds = "-sleepTimerSeconds"`,
  documented ("Followed by seconds: the 5-minute choice lasts that long"), added to `all`.
- Modify: `Abbay/DebugSupport/DebugOverrides.swift`: `static func sleepTimerSeconds(arguments:) -> TimeInterval?`
  (same shape as `readAlongControlsHideAfter`).
- Inject `SleepTimer` into the view tree the way `ReadAlongCenter` reaches `PlayerView`.
- Test: `AbbayTests/DebugOverridesTests.swift`: `test_sleepTimerSeconds_parsesTheNumber`,
  `test_sleepTimerSeconds_nilWithoutANumber`.

- [ ] Steps: failing tests → FAIL → implement → PASS → `xcodegen generate` and a full build →
  commit `feat(playback): wire the sleep timer app-wide, -sleepTimerSeconds for tests (#332)`.

### Task 5: The moon pill and its menu

**Files:**
- Create: `Abbay/View/PlayerView/SleepTimerPill.swift`
- Modify: `Abbay/View/PlayerView/PlayerView.swift` (`pills(compact:)`: after `VolumePill`)
- Modify: `Abbay/Core/AccessibilityID.swift`: `Player.sleepTimer = "player.sleepTimer"`
- Modify: `Localizable.xcstrings` + `Localizable.swift`
- Test: `AbbayTests/SleepTimerPillTests.swift`, `AbbayUITests/SleepTimerUITests.swift`

**Interfaces — produces:** `SleepTimerPill(timer: SleepTimer, book: AudioModel)`;
`static func accessibilityValue(choice: SleepTimerChoice?, remaining: TimeInterval?) -> String`;
`static func title(of choice: SleepTimerChoice) -> String`.

**Look:** a SwiftUI `Menu` whose label is `PlayerPill`: Off → `systemImage: "moon"`, no text, white;
end of chapter → `"moon.fill"`, no text, malachite; duration → `"moon.fill"` with
`PlayerProgressView.clockText(remaining)` (monospaced), `collapsesToIcon: true`, malachite, updated by
`TimelineView(.periodic(from: .now, by: 1))`. `.layoutPriority(2)` so Text (0) then Chapters (1)
lose their words first. Menu: the choices from `timer.choices(for:)`, then *Off*; the current one
has a checkmark. `accessibilityLabel` *Sleep timer*, value from `accessibilityValue`.

**Strings (en / pt-BR):** `sleepTimer` *Sleep timer* / *Timer de sono*; `sleepTimerOff` *Off* /
*Desligado*; `sleepTimerEndOfChapter` *When current chapter ends* / *Ao fim do capítulo atual*;
`sleepTimerMinutes` *%lld minutes* / *%lld minutos*; `sleepTimerOneHour` *1 hour* / *1 hora*;
`sleepTimerMinutesLeft` plural *%lld minute(s) left* / *%lld minuto(s) restante(s)*;
`sleepTimerUnderAMinute` *Less than a minute left* / *Menos de um minuto restante*.

- [ ] **Step 1: Failing unit tests:** `test_accessibilityValue_off` (*Off*),
  `test_accessibilityValue_roundsMinutesUp` (719 s → *12 minutes left*),
  `test_accessibilityValue_underAMinute` (59 s), `test_accessibilityValue_endOfChapter`,
  `test_title_ofEachChoice` (300 → *5 minutes*, 3600 → *1 hour*). Run → FAIL → implement → PASS.
- [ ] **Step 2: Failing UI tests** (launch: `seedLibrary`, `resetSettings`, `-sleepTimerSeconds 8`,
  en; open *Seeded Chaptered Book* as in `VolumeUITests.openPlayer`):
  - `test_sleepTimer_countsDown_thenPausesTheBook`: play; tap `player.sleepTimer`; tap *5 minutes*;
    the pill's value reads *Less than a minute left* and its label shows a countdown; within 15 s
    the play button reads *Play* (paused) and the pill's value is *Off*.
  - `test_sleepTimer_holdsWhilePaused`: set, pause at once, wait 10 s → value not *Off*.
  - `test_sleepTimer_offersEndOfChapter_onlyWithChapters`: menu on *Seeded Chaptered Book* has
    *When current chapter ends*; on *Seeded Plain Book* it doesn't.
  - `test_sleepTimer_pillsFit_withReadAlongOn` (`seedReadAlong`): with a timer running, the speed,
    volume, moon, Text and Chapters pills all exist and don't overlap (frames), on the test iPhone.
  Run → FAIL → wire the pill into `pills(compact:)` → PASS.
- [ ] **Step 3: Commit** `feat(player): the moon pill sets a sleep timer and counts it down (#332)`.

### Task 6: Docs, live check, PR 1

- [ ] `player.md`: a *sleep-timer* sub-feature (choices, counting, fade, ids, launch argument,
  what it isn't); the page's intro lists the moon pill. `StoreConfig/README.md`: drop "There's no
  sleep timer, so it isn't claimed."
- [ ] Live check on a simulator with `-sleepTimerSeconds 8`: set, count down, fade, pause; end of
  chapter on *Seeded Playable Book*; record what was driven.
- [ ] Pill row on an iPhone SE simulator and in landscape, at default and an accessibility text
  size, Read-along on and off: the speed and the running moon never truncate (spec *Room*).
- [ ] Screenshots before (`develop`) and after (branch), en and pt-BR, same simulator and seed,
  idle and running moon; committed to `pr-screenshots` under `pr-<n>/`.
- [ ] Gate: SwiftLint strict, the unit suite and the UI suite (own simulator,
  `-parallel-testing-enabled NO`), counts recorded.
- [ ] Issues for gaps (device check with the screen locked; CarPlay/Siri if wanted), linked in the PR.
- [ ] PR into `develop`: what shipped, tests (exact counts), feature-map pages, gaps, next (PR 2).

---

# PR 2: back to where you fell asleep (branch `feat/sleep-return`, from PR 1)

### Task 7: The listener's deliberate moves

**Files:** Modify `Abbay/Core/Player/Player.swift`, `AbbayTests/Mocks/MockPlayer.swift`,
`PlaybackCenter.swift`, `SleepTimer.swift`. Test: `PlayerFadeTests.swift`, `SleepTimerTests.swift`.

**Interfaces — produces:**
- `PlayerProtocol.listenerMovePublisher: AnyPublisher<Void, Never>` (default `Empty`): `Player`
  sends at the end of `play(_:)` and of `seek(_:)` (every skip, chapter tap and scrub goes through
  `seek`; a chapter ending into the next doesn't). `MockPlayer.emitListenerMove()`.
- `PlaybackEventObserving.listenerMoved(bookTime: Double)`, forwarded by `PlaybackCenter` with
  `player.currentTime`.
- `SleepTimerStop` gains `lastAwakeAt: Double` (S). The timer sets S on `set(_:)` (non-nil) and on
  `listenerMoved` while set.

- [ ] Failing tests: `test_seek_publishesAListenerMove`, `test_play_publishesAListenerMove`;
  `test_stop_carriesTheLastDeliberateMove` (set at 10, `listenerMoved(500)` → stop's
  `lastAwakeAt == 500`), `test_stop_withoutMoves_isWhereItWasSet`, `test_automaticTicks_dontMoveS`.
  FAIL → implement → PASS → commit `feat(playback): the sleep timer remembers the listener's last move (#332)`.

### Task 8: The saved spot

**Files:** Modify `Abbay/Core/Settings/AppSettings.swift`; Test `AbbayTests/AppSettingsTests.swift`.

**Interfaces — produces:** `struct SleepReturnSpot: Codable, Equatable { let returnTo: Double; let stoppedAt: Double }`;
`AppSettings.sleepReturnSpot(for url: URL?) -> SleepReturnSpot?`,
`AppSettings.setSleepReturnSpot(_ spot: SleepReturnSpot?, for url: URL?)`; observable; stored
under `abbay.settings.sleepReturnSpots` as a dictionary keyed by `url.absoluteString`, like
`bookSpeeds`.

- [ ] Failing tests: `test_sleepReturnSpot_roundTrips`, `test_sleepReturnSpot_survivesANewSettings`
  (same store), `test_sleepReturnSpot_nilClears`. FAIL → implement → PASS → commit.

### Task 9: SleepReturnCenter (the clearing rules)

**Files:** Create `Abbay/Core/Playback/SleepReturnCenter.swift`; modify `DependencyContainer`
(build after `sleepTimer`, `playback.addObserver`), inject like `SleepTimer`. Test
`AbbayTests/SleepReturnCenterTests.swift`.

**Interfaces — produces:**
```swift
@MainActor @Observable final class SleepReturnCenter: PlaybackEventObserving {
    init(settings: AppSettings, timer: SleepTimer, player: PlayerProtocol,
         savePosition: SavePlaybackPositionUseCaseProtocol = SavePlaybackPositionUseCase())
    func spot(for url: URL?) -> SleepReturnSpot?
    func goBack(for url: URL?)    // loaded: player.seek(returnTo); else save returnTo as the book's position
    func dismiss(for url: URL?)
    static let restartDistance: Double = 300     // book seconds from T
    static let listeningLimit: Double = 1800     // book seconds past T
}
```
Rules: `.stopped` saves `SleepReturnSpot(returnTo: lastAwakeAt, stoppedAt: stoppedAt)` for that
book; `.set(bookURL)` clears it; `playingChanged(true)` with the loaded book more than
`restartDistance` from `stoppedAt` clears it; `timeChanged` at or past `stoppedAt + listeningLimit`
clears it; `goBack` and `dismiss` clear it. Never starts playback.

- [ ] Failing tests: `test_timerStop_savesTheSpot`, `test_manualPause_savesNothing` (no event),
  `test_newTimer_clears`, `test_playNearTheStop_keeps` (start 120 s from T),
  `test_playFarFromTheStop_clears` (start 301 s from T), `test_listeningLimit_clears`,
  `test_goBack_seeksAndClears`, `test_goBack_onAnUnloadedBook_savesThePosition`,
  `test_dismiss_clears`, `test_goBack_doesNotPlay`. FAIL → implement → PASS → commit
  `feat(playback): keep where the listener fell asleep, per book (#332)`.

### Task 10: The prompt

**Files:** Create `Abbay/View/PlayerView/SleepReturnPromptView.swift`; modify `PlayerView.swift`
(an overlay beside `resumePromptOverlay`, hidden under the open panel and while a resume prompt
shows), `AccessibilityID.swift` (`Player.sleepReturn = "player.sleepReturn"`,
`sleepReturnGo = "player.sleepReturn.go"`, `sleepReturnDismiss = "player.sleepReturn.dismiss"`),
strings, `LaunchArgument`/`DebugOverrides`: `-seedSleepReturn` (with `seedLibrary`: *Seeded
Chaptered Book* gets `SleepReturnSpot(returnTo: 60, stoppedAt: 150)`). Test
`AbbayUITests/SleepTimerUITests.swift`.

**Look:** `ResumePromptView`'s glass capsule: 🌙 *Back to where you fell asleep* · `clockText(returnTo)`
(the whole leading part is the *go* button) and a ✕ (*Dismiss*). Announced on appear. No timeout.

**Strings:** `sleepReturnBack` *Back to where you fell asleep* / *Voltar para onde você
adormeceu*; `sleepReturnDismiss` *Dismiss* / *Dispensar* (reuse an existing key if one matches).

- [ ] Failing UI tests: `test_sleepReturn_seededSpot_showsAndGoesBack` (`-seedSleepReturn`: prompt
  shows *1:00*; tap go → the scrubber's time reads 1:00, prompt gone, still paused);
  `test_sleepReturn_dismiss`; `test_sleepReturn_afterATimerPause` (`-sleepTimerSeconds 8`, play,
  set 5 minutes, wait for the pause → prompt appears). FAIL → implement → PASS → commit
  `feat(player): back to where you fell asleep (#332)`.

### Task 11: Docs, live check, PR 2

- [ ] `player.md` *sleep-timer* gains the prompt (rules, ids, `-seedSleepReturn`);
  `StoreConfig/README.md` may name it.
- [ ] Live check, screenshots (en, pt-BR), gate, issues, PR into `develop` that closes #332.
