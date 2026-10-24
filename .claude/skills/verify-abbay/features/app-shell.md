# App shell

Launch, dependency wiring, audio-session activation and scene routing. Nothing else works if this
ordering breaks, and most of it is invisible in the UI.

## Sub-features

- **launch-ordering:** `AppDelegate.didFinishLaunchingWithOptions` runs a deliberately pinned
  sequence (`AppDelegate.didFinishLaunchingWithOptions`): `DependencyContainer.configure()` →
  `DebugOverrides.runLaunchSeeding()` (a no-op in Release) → `downloads.restore()` (re-attach to
  LibriVox download tasks and restart missing chapters) → audio-session activation → on success `LaunchStateFlag.clear()` + `seeder.seedIfNeeded()`, on failure
  `LaunchStateFlag.markUnavailable()` → `INPreferences.requestSiriAuthorization` →
  `SiriLibraryPublisher.publish`. The seams are `lazy var` on purpose: a non-lazy default argument
  would touch Core Data before `configure()` ran.
- **audio-session-flag:** `abbay.audioSessionUnavailable` in the App Group. Set when activation
  throws at launch, cleared on any later success. Every Siri intent and the extension's `decide`
  read it and bail out early, so a stale `true` silently disables all of Siri.
- **dependency-container:** `DependencyContainer.shared` traps with `fatalError` when unconfigured
  (`DependencyContainer.shared`). `isConfigured` exists precisely because AppIntents entity
  queries can run outside the launch path; those call sites fall back to the App Group snapshot.
- **scene-routing:** `configurationForConnecting` returns a CarPlay configuration for
  `carTemplateApplication`, otherwise the default `WindowGroup` hosting `AppRootView`
  (`configurationForConnecting`).
- **root:** `AppRootView` owns `MediaListViewModel`, `PlayerPresentation` and the selected tab, and
  injects `PlaybackState`, `PlaybackClock`, `PlaybackCenter`, `DownloadStateStore` and
  `PlayerPresentation` into the environment. Two tabs, Library and Search, each with its own
  `NavigationStack` (`root.tab.library`, `root.tab.search`). iOS 26.1+: the system `TabView` with
  two regular `Tab`s (no `role: .search`, which would move the Search field into the bottom tab bar;
  both search fields stay at the top). Identifiers are set on the `UITabBar` items by a small UIKit
  probe, since SwiftUI can't. iOS 17.0–26.0: the hand-built
  `RootTabs` bar. Above the tabs, `PlayerOverlay` presents `PlayerView` for
  `presentation.presentedBook` (interim: slides up; `player.close` or a drag down on its header
  closes it). Nothing presents the player as a sheet.
- **siri-authorisation:** requested on every launch. Without an explicit grant iOS refuses to
  dispatch to the extension and Siri answers "Abbay hasn't added support for that with Siri".
- **background-downloads:** `handleEventsForBackgroundURLSession` accepts only the download session
  (`com.edyuto.Abbay.downloads`) and passes the system's completion handler to the download manager;
  any other identifier is completed immediately. See [downloads](downloads.md).
- **dependency-container-downloads:** the container also builds the download manager
  (`BookDownloadManager.shared`, or the stand-in under `-stubLibriVox` in DEBUG) and hands it to the
  `Player` as its chapter prioritizer.
- **termination:** `applicationWillTerminate` calls `player.cleanup()`, which saves the current
  time and releases the security-scoped URL.

## How to get to it (user POV)

Cold launch from the home screen. The user sees the library immediately; everything in this file
happens before or behind that. The only user-visible failure mode is "Siri stopped working",
caused by the audio-session flag sticking.

## Driving it with abbay-ctl

```bash
$B doctor                                  # required: Xcode, simulator, build freshness, port ownership
$B launch                                  # terminate + reinstall + relaunch, returns a sessionId
$B launch --seed-library                   # -seedLibrary: two synthetic books, no playable audio
$B launch --reset-library                  # -resetLibrary: empty library (Core Data only; the App Group is untouched)
$B launch --stub-librivox                  # -stubLibriVox: in-memory catalog, no downloads, DEBUG builds only
$B launch --reset                          # planned: clear App Group + Core Data before launch
$B appgroup get abbay.audioSessionUnavailable
$B diagnostics                             # dump abbay.diagnostics.v1 (last 25 events)
$B diagnostics --clear
```

- `doctor` must report `STALE` when the app binary is older than any file under `Abbay/` — a proof
  against a stale build is not evidence.
- `doctor` must also refuse to drive while an `xcodebuild test` run holds the simulator.
- `--reset` has to clear state *before* the first scene connects, because `DataStack`'s container is
  `lazy` and `AppGroup.defaults` is a `static let` — both latch on first touch.

## Gotchas

- **A stale `audioSessionUnavailable` flag disables Siri entirely and the UI gives no hint.** Check
  it first whenever Siri "stops working". It is cleared only by a *successful* activation.
- `AppGroup.defaults` calls `fatalError` if the App Group is not provisioned
  (`AppGroup.swift:13`), and `didFinishLaunchingWithOptions` touches it during launch. A provisioning mismatch
  in a distribution build is therefore crash-on-launch for every user, not a degraded feature.
  `LastPlayedStore` has a `standardFallback`; this path has none.
- The launch ordering is covered by `AppDelegateOrderingTests` — change it and those fail by design.
- `LastPlayedStore` migrates once from `.standard` to the App Group suite, and clearing writes to
  *both* stores so a stale phase-1 value cannot resurface.
