# Downloads

`BookDownloadManager` and the views that show it — how a LibriVox book gets onto the device chapter
by chapter, keeps going in the background, can be streamed meanwhile, and is paused, resumed and
deleted. Not a screen of its own: it surfaces on the Library row, the
[LibriVox details page](librivox-details.md) and the [player](player.md) details screen.

## Sub-features

- **chapter-by-chapter:** one task per chapter file, at most **two at a time** per book, started in
  chapter order, in a background `URLSession` (`com.edyuto.Abbay.downloads`). Files land in
  `Application Support/LibriVox/<archive id>/`, excluded from backup. A chapter already on disk is
  never re-downloaded.
- **streaming:** `MultiFileQueue` plays a chapter's local file when it exists and its remote URL
  otherwise, so a book can be played while it is still downloading. Streaming ignores the cellular
  setting.
- **prioritize-on-jump:** whenever the player loads or advances to a chapter it asks the manager to
  move that chapter to the front of the queue (unless it is downloaded or already running).
- **pause-resume:** the progress ring on a Library row (`DownloadRingView`) pauses a running book and
  resumes a paused one; a paused ring shows a play glyph. Pausing stops the running tasks keeping
  resume data, and resuming continues from it. The paused flag is persisted per book.
- **failure:** a chapter that fails goes back to *Waiting* and is retried with a capped backoff: after
  30 s, then 2 min, then 10 min. A fourth failure in a row marks it *Failed · Retry*; tapping that
  status restarts it with a fresh backoff. A chapter that can't even start (`start`/`resume` throws)
  counts as a failure too. When the network path becomes satisfied again, every chapter waiting out a
  backoff or failed restarts at once. Jumping to a chapter in the player (prioritize) also resets its
  backoff. A task the system cancels (for example a force quit) is requeued rather than counted as a
  failure. Failure counts are in memory only: a relaunch starts every chapter fresh.
- **metered networks:** the >99 MB warning shows on any metered path: cellular, Personal Hotspot
  (`NWPath.isExpensive`) and Low Data Mode (`isConstrained`). A book without cellular (*Wait for
  Wi-Fi*, or a large book started on unmetered Wi-Fi) starts its tasks with `allowsCellularAccess`,
  `allowsExpensiveNetworkAccess` and `allowsConstrainedNetworkAccess` all off, so the system holds them
  on a hotspot or in Low Data Mode as well as on cellular. A resumed task keeps the settings of the
  request it was first started with.
- **restore:** on every launch (after any `-seedLibrary`/`-resetLibrary` seeding) `restore()`
  re-attaches to tasks the system kept running and restarts the missing chapters of every
  LibriVox book in the Library. The system can also relaunch the app in the background to deliver
  finished downloads (`handleEventsForBackgroundURLSession`).
- **delete:** deleting a LibriVox book cancels its tasks (dropping resume data) and deletes its
  directory. The player's position saves are update-only, so a deleted book that was loaded in the
  player is not re-inserted.
- **status-display:** a book's state is non-nil only while it is **incomplete**. The Library row shows
  the ring; the details screen and the LibriVox page show the overall progress bar and per-chapter
  ✓ / `N%` / *Waiting* / *Failed · Retry* through the shared `ChapterListView`. The failed status is
  a button (`player.chapter.<n>.retry`, `detail.chapter.<n>.retry`); a row showing it is an
  accessibility container rather than one combined element, so the button stays reachable. Imported books never show any of it.
  Library search rows tag a fully downloaded LibriVox book *Downloaded*.
  Every view reads the state through `DownloadStateStore`, the manager's one `statesPublisher`
  subscriber, which fans it out into one observable entry per book, so one book's progress only
  re-renders the views showing that book (`DownloadStateStoreTests`, `SubscriptionBudgetTests`).

## How to get to it (user POV)

Download a LibriVox book from its details page. Watch the ring on the Library row, open the book and
look at the chapter list; background the app or lock the phone and come back.

## Driving it with abbay-ctl

Real downloads are **not drivable in the UI-test configuration**: `-stubLibriVox` swaps in
`UITestDownloadManager`, whose `statesPublisher` is permanently empty and whose `enqueue`, `pause`,
`resume`, `remove`, `restore`, `prioritize` and `retry` do nothing. The ring, progress bar and statuses
therefore never render under the stub. A real run needs the network, no `-stubLibriVox`, and a
LibriVox book chosen deliberately small:

```bash
$B launch --seed-library                      # real catalog; needs network
$B tap root.tab.search
$B tap search.card.0 && $B tap detail.download
$B wait library.row.<n>.downloadRing          # planned: row index by title
$B tap library.row.<n>.downloadRing           # pause; again to resume
$B snapshot | jq '.elements[] | select(.id|startswith("detail.chapter"))'
$B terminate && $B launch                     # restore: ring and statuses come back
```

**Verified:** nothing in this file by UI test.

**Implemented but unverified** (attached in the views, never resolved by a UI test):
`library.row.<n>.downloadRing`,
`detail.progress`, `detail.chapter.<n>`, `detail.chapter.<n>.retry`, `player.download.progress`,
`player.chapter.<n>.retry`. A failed chapter can't be produced under `-stubLibriVox` at all.

**Unit-tested instead:** `BookDownloadManagerTests` (queue, concurrency, pause/resume, backoff and
cap, begin failures, tap-to-retry, restart when back online, restore, stale cancels, remove),
`CellularDownloadPolicyTests` and `NetworkPathSnapshotTests` (hotspot and Low Data Mode are metered),
`DownloadProviderTests` (no cellular also means no expensive or constrained network),
`MediaViewModelTests` (ring state, pause toggle), `ChapterListViewTests` (when statuses, progress and
the retry button show), `LibriVoxDetailViewModelTests` / `PlayerViewModelTests` (retry forwards to the
manager), `PlayerMultiFileTests` (prefers local file, prioritizes the chapter),
`LibriVoxPersistenceTests`.

**Not verified at all in this repo:** background transfer while the app is suspended or the phone is
locked, relaunch-by-the-system delivery, resume across a force quit, and cellular, Personal Hotspot
and Low Data Mode behaviour on a real network (including whether a background session honours the
request's expensive/constrained flags). These need a device (#128); only the manager's logic against
a mock provider is covered.

## Gotchas

- **Seeded books have no downloads.** `-seedLibrary` books carry no `librivoxID`, so they never show a
  ring or statuses regardless of launch arguments.
- **The ring appears only while incomplete.** A fully downloaded book, or one the manager has not been
  asked about, shows no ring. `MediaViewModel`, `PlayerViewModel` and the details page all filter on
  `!isComplete`.
- **Wait for Wi-Fi still enqueues.** The book is added and its chapters show *Waiting*; cellular,
  hotspots and Low Data Mode are simply not allowed for its tasks. With Low Data Mode on for the
  home Wi-Fi, such a book waits until it is turned off.
- **Pause is a toggle on a tiny target.** The ring is 22 pt; its accessibility label is
  *"Downloading, N%"* or *"Paused"*, which is the evidence for its state when no state id exists.
- A restored book is held in a restoring state until the manager knows which tasks are still running,
  so nothing starts twice; assertions straight after launch can see *Waiting* briefly.
- The manager keys everything by the archive.org identifier, not a LibriVox catalog ID; a
  `librivox://book/<id>` URL is the book's identity everywhere (library, snapshot, Now Playing).
