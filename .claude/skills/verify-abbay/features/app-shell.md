# App shell

Launch, dependency wiring, audio-session activation and scene routing. Nothing else works if this
ordering breaks, and most of it is invisible in the UI.

## Sub-features

- **launch-ordering:** `AppDelegate.didFinishLaunchingWithOptions` runs a deliberately pinned
  sequence (`AbbayApp.swift:27-53`): `DependencyContainer.configure()` → audio-session activation →
  on success `LaunchStateFlag.clear()` + `seeder.seedIfNeeded()`, on failure
  `LaunchStateFlag.markUnavailable()` → `INPreferences.requestSiriAuthorization` →
  `SiriLibraryPublisher.publish`. The seams are `lazy var` on purpose: a non-lazy default argument
  would touch Core Data before `configure()` ran.
- **audio-session-flag:** `abbay.audioSessionUnavailable` in the App Group. Set when activation
  throws at launch, cleared on any later success. Every Siri intent and the extension's `decide`
  read it and bail out early, so a stale `true` silently disables all of Siri.
- **dependency-container:** `DependencyContainer.shared` traps with `fatalError` when unconfigured
  (`DependencyContainer.swift:19`). `isConfigured` exists precisely because AppIntents entity
  queries can run outside the launch path; those call sites fall back to the App Group snapshot.
- **scene-routing:** `configurationForConnecting` returns a CarPlay configuration for
  `carTemplateApplication`, otherwise the default `WindowGroup` hosting `MediaListView`
  (`AbbayApp.swift:56-73`).
- **siri-authorisation:** requested on every launch. Without an explicit grant iOS refuses to
  dispatch to the extension and Siri answers "Abbay hasn't added support for that with Siri".
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
$B launch --seed-library                   # planned: import the bundled LibriVox fixture first
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
  (`AppGroup.swift:13`), and `AbbayApp.swift:32` touches it during launch. A provisioning mismatch
  in a distribution build is therefore crash-on-launch for every user, not a degraded feature.
  `LastPlayedStore` has a `standardFallback`; this path has none.
- The launch ordering is covered by `AppDelegateOrderingTests` — change it and those fail by design.
- `LastPlayedStore` migrates once from `.standard` to the App Group suite, and clearing writes to
  *both* stores so a stale phase-1 value cannot resurface.
