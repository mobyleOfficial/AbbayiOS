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
  failure. Failure counts are **persisted** (`ChapterFailureStore`, in `LocalStorage.preferences`
  under `downloads.chapterFailures`, keyed `<archive id>/<chapter file name>`): after a relaunch a
  chapter that had failed 1-3 times starts at once but its next failure waits the *next* delay, and a
  *Failed · Retry* chapter stays failed (not started) until tapped or the network comes back. A
  success, a tap, the network coming back, a file found on disk or deleting the book clears the count.
- **metered networks:** the >99 MB warning shows on any metered path: cellular, Personal Hotspot
  (`NWPath.isExpensive`) and Low Data Mode (`isConstrained`). A book without cellular (*Wait for
  Wi-Fi*, or a large book started on unmetered Wi-Fi) starts its tasks with `allowsCellularAccess`,
  `allowsExpensiveNetworkAccess` and `allowsConstrainedNetworkAccess` all off, so the system holds them
  on a hotspot or in Low Data Mode as well as on cellular. A resumed task keeps the settings of the
  request it was first started with, so tasks from before #134 (cellular off, hotspot and Low Data
  Mode still on) are re-created for such a book: `DownloadProvider.resume` refuses resume data whose
  archived request allows any metered network (`ResumeDataInspector`; unreadable resume data is
  kept) and the chapter starts afresh, and `restore()` cancels a still-running task whose request
  allows one (`runningIDsAllowingMeteredNetworks`, `cancel(ids:)`) and starts it again. Either way
  the chapter's progress so far is lost.
- **hold-hint:** while a *Wait for Wi-Fi* book (cellular not allowed) is incomplete and not paused,
  and the path is metered and online, the details screen and the LibriVox page say why under the
  progress bar, and the Library ring adds it to its label (#148, #171). The reason is
  `NetworkPathSnapshot.hold`, checked in this order:

  | Path | Text (en / pt-BR) | Ids (detail / player) | Glyph |
  |---|---|---|---|
  | cellular only | *Waiting for Wi-Fi: on cellular* / *Aguardando Wi-Fi: na rede celular* | `detail.cellularHold` / `player.download.cellularHold` | `antenna.radiowaves.left.and.right` |
  | expensive Wi-Fi (Personal Hotspot) | *Waiting for Wi-Fi: on a Personal Hotspot* / *Aguardando Wi-Fi: em um Acesso Pessoal* | `detail.hotspotHold` / `player.download.hotspotHold` | `personalhotspot` |
  | Wi-Fi in Low Data Mode | *Waiting: Low Data Mode is on* / *Aguardando: Modo Dados Reduzidos ativado* | `detail.lowDataMode` / `player.download.lowDataMode` | `wifi.exclamationmark` |

  Offline or on unmetered Wi-Fi there is no hint. Read through `DownloadStateStore.networkHold` /
  `hold(bookID:allowsCellular:)`, which reads the path only for a book it could hold, so idle rows
  don't follow it. The ring: see [media-row](media-row.md) *download-ring*.
- **restore:** on every launch (after any `-seedLibrary`/`-resetLibrary` seeding) `restore()`
  re-attaches to tasks the system kept running and restarts the missing chapters of every
  LibriVox book in the Library. The system can also relaunch the app in the background to deliver
  finished downloads (`handleEventsForBackgroundURLSession`).
- **delete:** deleting a LibriVox book cancels its tasks (dropping resume data) and deletes its
  directory. The player's position saves are update-only, so a deleted book that was loaded in the
  player is not re-inserted.
- **status-display:** a book's state is non-nil only while it is **incomplete**. The Library row shows
  the ring; the LibriVox page shows the overall progress bar and per-chapter
  ✓ / `N%` / *Waiting* / *Failed · Retry* (pt-BR *Falhou · Repetir*; statuses are one line at full
  width, the title wraps to two lines) through the shared `ChapterListView`. The details screen
  shows the overall progress line under its scrubber, and the per-chapter statuses in its chapter
  panel (#166 G2). A *finished* chapter (before the current one) that is downloaded shows only its
  finished check, not a second ✓ (#225, `ChapterListView.shownStatus`). The failed status is
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
`UITestDownloadManager`, which downloads nothing. Alone, its `statesPublisher` stays empty. With
**`-stubDownloadStates`** (#171) the stub book is 120 MB in three chapters, and every book enqueued gets
a fixed state: chapter 0 downloaded, 1 waiting, 2 failed (33%); pause and resume flip `isPaused` and
retry sets the chapter back to waiting. **`-stubPathCellular`**, **`-stubPathHotspot`** or
**`-stubPathLowDataMode`** fix the path the download screens read (`NetworkPathMonitor.app`), so
Download asks and *Wait for Wi-Fi* produces each hold:

```bash
$B launch -stubLibriVox -resetLibrary -resetSettings -stubDownloadStates -stubPathCellular
$B tap root.tab.search && $B tap search.card.0
$B tap detail.download && $B tap detail.cellular.wait     # the 120 MB alert
$B wait detail.progress && $B wait detail.cellularHold    # "Waiting for Wi-Fi: on cellular"
$B tap detail.chapter.2.retry                             # the retry button goes away
$B tap root.tab.library && $B wait library.row.0.downloadRing
# label "Downloading, 33%. Waiting for Wi-Fi: on cellular"; tap → "Paused"
$B tap library.row.0.title && $B wait player.download.cellularHold
```

Real transfers still need the network, no `-stubLibriVox`, and a LibriVox book chosen deliberately
small:

```bash
$B launch -seedLibrary                        # real catalog; needs network
$B tap root.tab.search
$B tap search.card.0 && $B tap detail.download
$B wait library.row.<n>.downloadRing          # planned: row index by title
$B tap library.row.<n>.downloadRing           # pause; again to resume
$B snapshot | jq '.elements[] | select(.id|startswith("detail.chapter"))'
$B terminate && $B launch                     # restore: ring and statuses come back
```

**Verified** by `DownloadStatusUITests`, under the stubs above: `detail.progress`,
`detail.cellularHold`, `detail.hotspotHold`, `detail.lowDataMode` (with their en texts),
`detail.chapter.2.retry` and retrying it, no hint after *Continue* (`detail.cellular.continue`),
`player.download.progress`, `player.download.cellularHold`, `player.download.hotspotHold`,
`player.download.lowDataMode`, `player.chapter.2.retry`, and `library.row.0.downloadRing` (its held
label, then *Paused* once tapped).

**Unverified by UI test:** anything to do with real transfers (below).

**Unit-tested instead:** `BookDownloadManagerTests` (queue, concurrency, pause/resume, backoff and
cap, begin failures, tap-to-retry, restart when back online, restore, stale cancels, remove,
failures kept across a relaunch, metered pre-#134 tasks restarted on restore),
`ChapterFailureStoreTests`, `ResumeDataInspectorTests` and `DownloadProviderTests` (resume data
allowing metered networks refused, `runningIDsAllowingMeteredNetworks`, `cancel(ids:)`),
`DownloadStateStoreTests` (which book a path holds, and that idle rows don't read the path),
`LocalizationTests` (statuses stay short, the ring's held label),
`CellularDownloadPolicyTests` (hotspot and Low Data Mode are metered; `NetworkPathSnapshot.hold` for
every path, set exactly when the path is metered and online),
`DebugOverridesTests` (the `-stubDownloadStates` / `-stubPath*` stand-ins),
`DownloadProviderTests` (no cellular also means no expensive or constrained network),
`MediaViewModelTests` (ring state, pause toggle), `ChapterListViewTests` (when statuses, progress and
the retry button show), `LibriVoxDetailViewModelTests` / `PlayerViewModelTests` (retry forwards to the
manager), `PlayerMultiFileTests` (prefers local file, prioritizes the chapter),
`LibriVoxPersistenceTests`.

**Not verified at all in this repo:** background transfer while the app is suspended or the phone is
locked, relaunch-by-the-system delivery, resume across a force quit, and cellular, Personal Hotspot
and Low Data Mode behaviour on a real network (including whether a background session honours the
request's expensive/constrained flags), and the hold hints on a real cellular, hotspot or
constrained Wi-Fi path (whether `NWPath` reports them as `NetworkPathSnapshot.hold` expects). These
need a device (#128); only the manager's logic against a mock provider is covered.
`ResumeDataInspector` was checked against real resume data from a macOS URLSession download (its
format: a keyed archive under `NSKeyedArchiveRootObjectKey` whose request entries are archived
`NSMutableURLRequest`s); iOS resume data from the background session is a device check (#128).
The hints and the shorter pt-BR status were first driven with a temporary stub (#148's PR); since
#171 the committed `-stubDownloadStates` / `-stubPath*` arguments do it.

## Gotchas

- **Seeded books have no downloads.** `-seedLibrary` books carry no `librivoxID`, so they never show a
  ring or statuses regardless of launch arguments.
- **The ring appears only while incomplete.** A fully downloaded book, or one the manager has not been
  asked about, shows no ring. `MediaViewModel`, `PlayerViewModel` and the details page all filter on
  `!isComplete`.
- **Wait for Wi-Fi still enqueues.** The book is added and its chapters show *Waiting*; cellular,
  hotspots and Low Data Mode are simply not allowed for its tasks. On any of them such a book waits,
  and says which (*hold-hint*).
- **Failure counts outlive a relaunch, not a reinstall.** They live in the app's
  `UserDefaults`; deleting the app clears them with the files.
- **Pause is a toggle on a tiny target.** The ring is 22 pt; its accessibility label is
  *"Downloading, N%"*, *"Downloading, N%. <hold text>"* or *"Paused"*, which is the evidence for its
  state when no state id exists.
- A restored book is held in a restoring state until the manager knows which tasks are still running,
  so nothing starts twice; assertions straight after launch can see *Waiting* briefly.
- The manager keys everything by the archive.org identifier, not a LibriVox catalog ID; a
  `librivox://book/<id>` URL is the book's identity everywhere (library, snapshot, Now Playing).
