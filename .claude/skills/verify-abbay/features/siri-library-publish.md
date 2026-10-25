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
  Spotlight's completion handlers have run (none, for an unchanged library, #173). `updateAppShortcutParameters()`,
  `INVocabulary` and `becomeCurrent()` are synchronous with no completion API, so whatever the
  system does after they return can't be waited for. iOS decides when, or whether, it
  runs. Drop it if the device judgement in #127 shows no improvement.
- **snapshot:** `abbay.librarySnapshot.v1` in the App Group — a versioned `LibrarySnapshot` of
  `{title, urlString, bookmarkData, artist}`. The extension's only data source. `artist` (#201,
  omitted when empty; older snapshots decode without it) lets Siri match "\<title> by
  \<author>".
- **spotlight:** `LibrarySpotlightIndexer` indexes each book as a `CSSearchableItem` in a named index
  with `completeUntilFirstUserAuthentication` protection, so the system can read it while locked.
  Skips books with no URL or an empty title; two rows under one URL are one item. **The index
  mirrors the library (#195), and each publish only sends the change (#173).** The indexer keeps
  a record, `abbay.spotlightIndexRecord.v1` in the app's own `UserDefaults`
  (`LocalStorage.preferences`, injected as `store:`), of `[identifier: fingerprint]` for what the
  index holds. The fingerprint is a SHA-256 of `SpotlightItemContent` (identifier, title, artist,
  album: everything the item carries; there is no artwork in the item), so the record holds no
  titles. Each publish diffs the library against the record: items whose book left the library
  (or lost its title) are deleted with `deleteSearchableItems(withIdentifiers:)`, new and changed
  ones are indexed, and the record is saved. **An unchanged library makes no Core Spotlight
  call** (`spotlight: unchanged, N items`, `.debug`); a change logs `spotlight: indexed N, deleted
  M`. **Rebuild:** with no record (fresh install, first publish after updating to #173, or a
  failed rebuild) the publish clears the domain `com.edyuto.Abbay.library`
  (`deleteSearchableItems(withDomainIdentifiers:)`) and indexes every book, which also removes
  identifiers no longer used (a moved book's pre-#186 resolved URL); logged `spotlight: rebuilt, N
  items (no record)`. If the incremental delete or index fails (`spotlight deleting failed:` /
  `spotlight indexing failed: <domain> <code>`), the same publish falls back to that rebuild once
  (`… (after a failure)`). The rebuild drops the record first and saves it only when both the
  clear and the index succeed, so a crash or failure midway makes the next publish rebuild again.
  A failed clear logs `spotlight clearing failed: <domain> <code>` and the books are indexed
  anyway. An empty library with no record clears; with a record it deletes the remaining items.
  One update runs at a time: a publish that arrives meanwhile waits, a newer one supersedes it,
  and every waiting caller completes once the latest library is indexed. Unit-tested against a
  fake index (`LibrarySpotlightIndexerTests`).
- **spotlight re-index requests (#205):** `SpotlightReindexDelegate` (`Abbay/Core/`) is the named
  index's `CSSearchableIndexDelegate`, attached in `didFinishLaunching` before the launch publish
  (`LibrarySpotlightIndexer.attach`; held by `AppDelegate`, the index keeps it weakly). When the
  system asks for every item again (`reindexAllSearchableItemsWithAcknowledgementHandler`) it logs
  `spotlight: the system asked to re-index everything`, calls `forgetIndexedItems(nil)` and
  publishes with `SiriContextRefresher.refreshNow(.spotlightReindex)` on main (log `context refresh
  (spotlightReindex): N books`); that publish rebuilds (`spotlight: rebuilt, N items (the system
  asked)`) and the system is acknowledged when it has finished. Asked for some identifiers
  (`reindexSearchableItemsWithIdentifiers`), it logs `… re-index N items` and forgets only those:
  the publish indexes them as additions, without clearing. A forget is held in memory and applied
  when the next update starts, so an update already in flight can't save its record over it, and
  requests before that update add up (one for everything wins). Unit-tested with fake delegate
  calls (`SpotlightReindexDelegateTests`, `LibrarySpotlightIndexerTests`). The requests reach the
  delegate only while the app runs; a request made while it doesn't needs a Core Spotlight index
  extension (#218). **No launch self-check:** probing the index with `CSSearchQuery` was tried
  and rejected for #205: `uniqueIdentifier == "…"` never finds an item (0 results, no error), and
  `domainIdentifier == "com.edyuto.Abbay.library"` / `title == "…"` find it but took 69–114 s on a
  cold iOS 27.0 simulator (a few ms warm); `*` fails with `CSSearchQueryErrorDomain -2002`.
- **entity-queries:** `AudiobookEntityQuery` (40 suggestions), `ChapterEntityQuery` (50) and
  `AuthorEntityQuery` (15, #213; the library's distinct artists) back the
  entity parameters. All implement `EntityStringQuery` so Siri can match a spoken string.
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
`Siri` category (`context refresh (foreground|pause|interruption|carPlay|backgroundTask|spotlightReindex): N books`,
`… skipped … throttled`, `publish: N books` (#157, `.info`, count only), `publish: finished in
N ms` (`.info`, #173: from the publish's start to Spotlight's completion, waiting behind an
earlier publish included), `spotlight: unchanged, N items` (`.debug`), `spotlight: indexed N,
deleted M`, `spotlight: rebuilt, N items (no record|after a failure|the system asked)`, `spotlight: the system asked to re-index (everything|N items)`, `spotlight indexing failed:
<domain> <code>`, `spotlight deleting failed: <domain> <code>`, `spotlight clearing failed:
<domain> <code>`, `background refresh: publish finished`,
`background refresh: …`). Read `.info`/`.debug` with `log stream --level debug` or `log show --info --debug`. On the simulator `BGTaskScheduler.submit` is refused (logged,
expected). To fire the task on a device under the debugger, pause and run
`e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.edyuto.Abbay.siriRefresh"]`.
Unit-tested by `SiriContextRefresherTests`, `SiriBackgroundRefreshTests` (incl. completion order),
`AppDelegateSiriFreshnessTests`, `PlayerSiriFreshnessTests` (incl. interruptions),
`CarPlaySceneDelegateTests` and `SiriLibraryPublisherTests`. `SiriLibraryPublisher` and
`LibrarySpotlightIndexer` log the publish and `spotlight …` lines above
through an injected `SiriLogSink` (`Abbay/Core/SiriLog.swift`): `OSSiriLogSink` writes them to
`Log.siri` with every field `.public`, and the `SiriLogEvent` cases carry only counts and error
domains/codes, so titles have nowhere to go. Tests assert on `RecordingSiriLogSink`; no unit test
reads the unified log (`OSLogStore` missed entries late in full-suite runs, #181). The exact
`os.Logger` text, level and privacy come from the pure `SiriLogEvent.record` and are pinned by
`SiriLogRecordTests` (#190); `OSSiriLogSink` only forwards the record to `Log.siri`. Since #197 the
same holds for every other line here: `SiriContextRefresher` (`context refresh …`, `… skipped …
throttled`) and `SiriBackgroundRefresh` (`background refresh: registration refused for <id>`,
`not scheduled: <domain> <code>`, `expired`, `publish finished`) log `SiriLogEvent`s through an
injected `SiriLogSink`, and `LibrarySnapshotWriter` logs `LibrarySnapshotLogEvent`s
(`snapshot WRITTEN: …`, `snapshot WRITE FAILED: JSON encode error`) through an injected closure.
All of them are pinned in `SiriLogRecordTests`; the call sites are covered by
`SiriContextRefresherTests`, `SiriBackgroundRefreshTests` and `LibrarySnapshotWriterTests`. A live
`log stream` read remains the check that the wrapper (`Logger.write(_:)` in `Log.swift`) itself
writes.

`AppIntentsTesting` (Xcode 27) is now in use for the iOS 27 audio domain (`AudioDomainUITests`, see
[siri-app-intents](siri-app-intents.md)); it could also validate these entity queries and
Spotlight indexing directly.

## Gotchas

- **Spotlight can be very slow, and the background task waits for it (#159).** On a freshly
  booted iOS 26.4 simulator, a clear plus re-index of 14 books took 130–282 s (#173's PR; ~42 s
  for 2 books in #159); on a warm one, 0.3–12 s. A `BGAppRefreshTask` gets about 30 s. Since
  #173 an unchanged library (the daily background run's usual case) makes no Core Spotlight call,
  and its publish finished in 1.2–1.5 s cold, which is the synchronous Siri registrations and the
  main-queue hop. A one-book add or delete took 0.1 s warm; not measured cold, and a rebuild (no
  record) is as slow as before. Device measurement tracked in #173.
- **Publishing on every launch is deliberate — do not "optimise" it away.** The comment at
  the comment in `didFinishLaunchingWithOptions` records why: without one successful entity fetch, entity phrases never
  resolve.
- **LibriVox books publish as ordinary entries, by assumption.** `addLibriVoxBook` rewrites the
  snapshot, so a downloaded book is in `abbay.librarySnapshot.v1` with its `librivox://book/<id>` as
  `urlString` and a null bookmark (`IntentRouter` loads it by that identifier).
  The publishing, Spotlight and entity-query code is unchanged on this branch and no test builds a
  snapshot from a LibriVox model; resolution of "Play <title> in Abbay" for such a book is unverified.
- `bookmarkData` is written only when non-empty, and books are only bookmarked on first *play*. A
  freshly imported library publishes titles with null bookmarks, which still resolve by their
  identifier but are fragile if the file moves.
- **`urlString` is the book's identity (#186):** the URL its row was saved under, never where a
  moved file resolves now, so entity ids, donations and Spotlight ids keep matching the row after
  the file moves (`MovedBookIdentityTests`). An item published under a moved book's resolved URL
  before #186 is cleared by the first publish after updating to #173, which has no record and so
  rebuilds (#195). An item the record doesn't know about is otherwise never seen: only a rebuild
  clears the whole domain.
- `LibrarySnapshotWriter` logs through `Log.librarySnapshot` (category `LibrarySnapshot`) with
  `.public` counts. The subsystem is the running bundle's, so a write from the extension (none today)
  would log under `com.edyuto.Abbay.AbbayIntents`, not the app's.
  `$B launch -seedLibrary` logs `snapshot WRITTEN: 2 entries (0 with bookmark),
  suite=group.com.edyuto.abbay` under `[com.edyuto.Abbay:LibrarySnapshot]`.
- When *every* book is filtered out (an all-untitled library) the indexer indexes nothing, so such
  a library has no Spotlight items.
- **The record trusts the index (#173).** If the system loses the app's items while the record is
  kept (Spotlight's own index reset, or a restore from a backup that carries `UserDefaults`), the
  next publishes see no change and don't re-index, **until the system asks**: since #205 the
  re-index request forgets the record and the publish it triggers rebuilds. Whether, and when, iOS
  sends that request after such a loss is the system's call and unobserved; a request while the
  app isn't running is not received (#218). Deleting the app removes both. To force a rebuild while testing, delete the app or remove
  `abbay.spotlightIndexRecord.v1` from its defaults (`xcrun simctl spawn <udid> defaults delete
  com.edyuto.Abbay abbay.spotlightIndexRecord.v1`).
- Whether a deleted book also leaves the Spotlight *search screen* promptly on a device is part of
  #173's device check. On the simulator the clear was checked by reading the index back in-process
  with `CSSearchQuery` (the PR for #195).
- `SiriLibraryPublisher.shared` is a `let` since #153: `LibrarySnapshotWriter` and
  `SiriContextRefresher` take their publisher as an init argument, which is where tests inject a
  spy (and where `NoopSiriLibraryPublisher` keeps a real writer off Siri), and the publisher takes
  its `SiriDiagnostics` trail. `LibrarySpotlightIndexer.shared` and `LibrarySnapshotWriter.shared`
  are still `static var`s tests can rebind. Rebind in `setUp`, restore in
  `tearDown`, or tests leak into each other.
