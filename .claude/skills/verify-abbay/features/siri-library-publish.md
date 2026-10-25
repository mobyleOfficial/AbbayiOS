# Siri — library publishing

Everything that teaches the system what Abbay's books are called, so a spoken title resolves. Not
user-facing, but every title-matching Siri phrase depends on it.

## Sub-features

- **publish-on-launch:** `AppDelegate` calls `SiriLibraryPublisher.publish(audios:)` on **every**
  launch (`didFinishLaunchingWithOptions`). Apple requires at least one successful entity fetch before
  entity-parameter phrases resolve at all, and the snapshot seeder only writes when the snapshot is
  missing, so launch cannot rely on the write path.
- **publish-on-mutation:** `LibrarySnapshotWriter.write` calls the publisher at the end, guarded out
  of the extension build. Every import and delete therefore refreshes Siri's view.
- **publish-on-foreground, pause, interruption and CarPlay (#127, #160, experiment):**
  `SiriContextRefresher` re-publishes the library when the scene becomes active (`AbbayApp` →
  `AppDelegate.scenePhaseChanged`), on every `Player.pause()`, when an audio-session interruption
  begins while the user had asked to play (reason `interruption`), and when the CarPlay scene
  connects or becomes active (`CarPlaySceneDelegate.carPlayBecameActive`, reason `carPlay`; a
  CarPlay-only session with the phone locked never makes the window scene active), all at most once
  per `SiriContextRefresher.minimumInterval` (10 minutes,
  in-memory clock). Launch's snapshot write calls `markPublished()`, so the first foreground after a
  cold launch doesn't publish twice. Library mutations publish through the snapshot writer and do
  not restart the throttle.
- **daily background refresh (#127, experiment):** `SiriBackgroundRefresh` registers the
  `BGAppRefreshTask` `com.edyuto.Abbay.siriRefresh` (listed in `BGTaskSchedulerPermittedIdentifiers`,
  background mode `fetch`) at launch, schedules it a day out each time the scene goes to the
  background, reschedules on every run, publishes with `refreshNow` (ignores the throttle) and
  completes the task once, **after the publish reports completion** (#159) — unsuccessfully if it
  expires first. `SiriLibraryPublisher.publish(audios:completion:)` completes on main once
  Spotlight's `indexSearchableItems` completion handler has run. `updateAppShortcutParameters()`,
  `INVocabulary` and `becomeCurrent()` are synchronous with no completion API, so whatever the
  system does after they return can't be waited for. iOS decides when, or whether, it
  runs. Drop it if the device judgement in #127 shows no improvement.
- **snapshot:** `abbay.librarySnapshot.v1` in the App Group — a versioned `LibrarySnapshot` of
  `{title, urlString, bookmarkData}`. The extension's only data source.
- **spotlight:** `LibrarySpotlightIndexer` indexes each book as a `CSSearchableItem` in a named index
  with `completeUntilFirstUserAuthentication` protection, so the system can read it while locked.
  Skips books with no URL or an empty title.
- **entity-queries:** `AudiobookEntityQuery` (40 suggestions) and `ChapterEntityQuery` (50) back the
  entity parameters. Both implement `EntityStringQuery` so Siri can match a spoken string.
  `ChapterEntity.currentBook()` resolves chapters against whatever is playing.
- **shortcut-parameter refresh:** `AbbayAppShortcuts.updateAppShortcutParameters()`, called only by
  `SiriLibraryPublisher.publish`, so once per snapshot write: import, LibriVox add
  (`MediaListViewModel.addLibriVoxBook`), delete and cold launch. Nothing else calls it directly
  (#84 removed the view model's second call;
  `test_importAndAddLibriVoxBook_publishToSiriOnceEach`).
- **media-affinity:** `MediaUserContextDonor` and `IntentDonor.donatePlayMedia` donate interactions
  so the system learns to prefer Abbay for audiobook requests. `IntentDonor` donates at play start,
  on pause and when a playing tick crosses into another chapter (#127); see
  [siri-playmedia](siri-playmedia.md).

## How to get to it (user POV)

Invisible. It manifests as whether *"Play \<title> in Abbay"* resolves at all, and whether Abbay
appears in Spotlight search for a book title.

## Driving it with abbay-ctl

```bash
$B launch -seedLibrary
$B appgroup get abbay.librarySnapshot.v1 | jq '.audios | length'
$B appgroup get abbay.librarySnapshot.v1 | jq '[.audios[] | select(.bookmarkData != null)] | length'
$B spotlight query "<title>"                  # planned: CSSearchQuery against our named index
```

The refreshes and the background task are not observable from the app's state: they log to the
`Siri` category (`context refresh (foreground|pause|interruption|carPlay|backgroundTask): N books`,
`… skipped … throttled`, `publish: N books` (#157, `.info`, count only), `publish: finished`
(`.debug`), `spotlight indexing failed: <domain> <code>`, `background refresh: publish finished`,
`background refresh: …`). Read `.info`/`.debug` with `log stream --level debug` or `log show --info --debug`. On the simulator `BGTaskScheduler.submit` is refused (logged,
expected). To fire the task on a device under the debugger, pause and run
`e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.edyuto.Abbay.siriRefresh"]`.
Unit-tested by `SiriContextRefresherTests`, `SiriBackgroundRefreshTests` (incl. completion order),
`AppDelegateSiriFreshnessTests`, `PlayerSiriFreshnessTests` (incl. interruptions),
`CarPlaySceneDelegateTests` and `SiriLibraryPublisherTests`. `SiriLibraryPublisher` and
`LibrarySpotlightIndexer` log `publish: N books`, `publish: finished` and `spotlight indexing failed`
through an injected `SiriLogSink` (`Abbay/Core/SiriLog.swift`): `OSSiriLogSink` writes them to
`Log.siri` with every field `.public`, and the `SiriLogEvent` cases carry only counts and error
domains/codes, so titles have nowhere to go. Tests assert on `RecordingSiriLogSink`; no unit test
reads the unified log (`OSLogStore` missed entries late in full-suite runs, #181). The exact
`os.Logger` text, level and privacy come from the pure `SiriLogEvent.record` and are pinned by
`SiriLogRecordTests` (#190); `OSSiriLogSink` only forwards the record to `Log.siri`. A live
`log stream` read remains the check that the wrapper itself writes.

`AppIntentsTesting` can validate entity queries and Spotlight indexing directly, which makes this
feature one of the better arguments for taking the Xcode 27 upgrade.

## Gotchas

- **Spotlight indexing is slow, and the background task waits for it (#159).** On the iOS 26.4
  simulator `publish: finished` came ~42 s after `publish: 2 books`; a `BGAppRefreshTask` gets
  about 30 s, so the task may expire before indexing ends. Device measurement tracked in #173.
- **Publishing on every launch is deliberate — do not "optimise" it away.** The comment at
  the comment in `didFinishLaunchingWithOptions` records why: without one successful entity fetch, entity phrases never
  resolve.
- **LibriVox books publish as ordinary entries, by assumption.** `addLibriVoxBook` rewrites the
  snapshot, so a downloaded book is in `abbay.librarySnapshot.v1` with its `librivox://book/<id>` as
  `urlString` and a null bookmark (the URL fallback in `IntentRouter.resolveURL` then loads it).
  The publishing, Spotlight and entity-query code is unchanged on this branch and no test builds a
  snapshot from a LibriVox model; resolution of "Play <title> in Abbay" for such a book is unverified.
- `bookmarkData` is written only when non-empty, and books are only bookmarked on first *play*. A
  freshly imported library publishes titles with null bookmarks, which still resolve via the URL
  fallback but are fragile if the file moves.
- `LibrarySnapshotWriter` logs through `Log.librarySnapshot` (category `LibrarySnapshot`) with
  `.public` counts. The subsystem is the running bundle's, so a write from the extension (none today)
  would log under `com.edyuto.Abbay.AbbayIntents`, not the app's.
  `$B launch -seedLibrary` logs `snapshot WRITTEN: 2 entries (0 with bookmark),
  suite=group.com.edyuto.abbay` under `[com.edyuto.Abbay:LibrarySnapshot]`.
- The Spotlight indexer returns early when *every* item is filtered out, so an all-untitled library
  silently indexes nothing.
- `SiriLibraryPublisher.shared` is a `let` since #153: `LibrarySnapshotWriter` and
  `SiriContextRefresher` take their publisher as an init argument, which is where tests inject a
  spy (and where `NoopSiriLibraryPublisher` keeps a real writer off Siri), and the publisher takes
  its `SiriDiagnostics` trail. `LibrarySpotlightIndexer.shared` and `LibrarySnapshotWriter.shared`
  are still `static var`s tests can rebind. Rebind in `setUp`, restore in
  `tearDown`, or tests leak into each other.
