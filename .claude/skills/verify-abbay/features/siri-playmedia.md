# Siri — INPlayMediaIntent

The legacy SiriKit media path. Abbay handles `INPlayMediaIntent` in **two** places, and which one
iOS picks is not fully under the app's control. This is the murkiest part of the app.

## Sub-features

- **extension path:** `AbbayIntents` is an intents-service app extension
  (`NSExtensionPointIdentifier: com.apple.intents-service`). `IntentHandler.handler(for:)` returns
  `PlayMediaIntentHandler`, whose `decide(for:)` returns a `ResolveOutcome`: `unavailable`,
  `emptyLibrary`, `noMatch`, `singleMatch`, `disambiguation` (2-5 items) or `fallbackBest` (>5).
- **in-app path:** the app also declares `INIntentsSupported`, so iOS can dispatch straight to
  `AppDelegate.application(_:handlerFor:)` → `InAppPlayMediaHandler`, which runs the full
  resolve → confirm → handle lifecycle. Supplying only `application(_:handle:)` makes Siri speak a
  generic error even when playback succeeds, which is why the handler object exists.
- **routing:** `IntentRouter.handle` is the shared tail. It bails on
  `LaunchStateFlag.isUnavailable()`, finds an identifier (from the resolved media item if the
  extension already matched, otherwise by matching `mediaSearch.mediaName` itself), loads the
  model, and plays.
- **url-resolution (#186):** the identifier is the book's identity, its row's URL, so it is loaded
  as is (a moved book plays from where its file is now; see [import](import.md) *identity*). On a
  miss, `rowURL(resolvingTo:)` looks for the snapshot book whose bookmark resolves to the
  identifier: a donation from before #186 named a moved book by its resolved URL. A stale bookmark
  needs nothing here: loading the book saves the fresh one (#146).
- **matching:** `MediaSearchResolver.candidates` over `FuzzyMatch`, biased toward
  `LastPlayedStore.lastPlayedURL()` so a titleless "play" resumes the right book.
- **stuck-state guards:** a dead pointer clears `LastPlayedStore` only when the dead URL *is* the
  saved one, then refreshes the snapshot.
- **recency donations (#127, experiment):** `IntentDonor.donatePlayMedia` donates an
  `INPlayMediaIntent` interaction with the book as an `INMediaItem` at play start (`Player.play`),
  on `Player.pause()` (every pause path: app, lock screen, CarPlay, Siri, book end) and when a
  playing tick lands in a different chapter than the last one (`Player.noteChapter`, which also
  catches chapter skips). A repeat for the same book inside `IntentDonor.repeatWindow` (2 minutes)
  is dropped and doesn't restart the window. An `AVAudioSession` interruption (call, Siri, another
  app's audio) that begins while the user had asked to play donates too (#160): `Player` tracks the
  play request itself (`isPlayRequested`), since the system has already paused the queue player when
  the notification arrives. Donations pass a completion handler; a failure logs
  `donation failed: <domain> <code>` to the `Siri` category at `.error`, never the title (#157).
  The line goes through an injected `SiriLogSink` (`OSSiriLogSink` → `Log.siri` in the app); its
  `SiriLogEvent` carries only the domain and code, so a title can't reach it. `IntentDonorLoggingTests`
  assert on a recording sink, not the unified log (#181); `SiriLogRecordTests` pin the exact text,
  level and `.public` privacy `OSSiriLogSink` writes (#190).
- **cross-process state:** the extension cannot touch Core Data. It reads
  `abbay.librarySnapshot.v1` from the App Group, which the app writes on every library mutation.
  `LibrarySnapshotWriter` compiles a no-op `LoadAllAudios` under `ABBAY_INTENTS_EXTENSION`.

## How to get to it (user POV)

*"Play \<title> on Abbay"*, *"Play Abbay"*, or any media-domain phrase Siri routes to the app.

## Driving it with abbay-ctl

`verified-unreachable` for the voice path. The reachable assertions:

```bash
$B appgroup get abbay.librarySnapshot.v1      # the extension's only view of the library
$B diagnostics                                # "ext decide entered" vs "app handleInApp received"
                                              # tells you WHICH path handled the request
$B appgroup get abbay.audioSessionUnavailable
```

`SiriDiagnostics` is the single most useful tool here: the extension records `ext …` and the in-app
handler records `app …`, so one log read establishes which of the two paths iOS chose. The
unified log adds per-step detail: the extension logs each `decide` step through
`Log.playMediaIntent` (subsystem `com.edyuto.Abbay.AbbayIntents`, category `PlayMediaIntent`), with
the spoken name and last-played URL `.private` and counts and the flag `.public`. These are
`.info` entries, so read them with `--info`, e.g.
`xcrun simctl spawn booted log show --last 5m --info --predicate 'subsystem BEGINSWITH "com.edyuto.Abbay"'`.
Note that `AppIntentsTesting` does **not** cover this — it is App Intents only. This path stays unit-tested
(`InAppPlayMediaHandlerTests`, `IntentRouterTests`, `SiriEntityTests`).

## Gotchas

- **Two handlers for one intent type is the most likely source of #90.** Siri routing between the
  extension and the in-app handler differs by context, and CarPlay may resolve differently from the
  phone. `docs/superpowers/research/2026-09-12-siri-routing-diagnosis.md` has prior findings.
- The extension sees **only** the App Group snapshot. If the snapshot is stale or empty, the
  extension reports `emptyLibrary` while the app's own library is fine. Every library mutation must
  go through `LibrarySnapshotWriter.write`.
- A book imported but never played has no bookmark in the snapshot, so the extension can only offer
  the raw URL string and resolution depends on the fallback.
- Apple now documents SiriKit / Intents / IntentsUI as **legacy**, pointing at App Intents. Any
  rework should move toward the App Intents path rather than deepening this one — relevant to #81.
- `INPreferences.requestSiriAuthorization` must have been granted or iOS refuses extension dispatch
  entirely, answering "Abbay hasn't added support for that with Siri".
