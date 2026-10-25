# LibriVox details page

`LibriVoxDetailView` — the page pushed in the **Search tab** from a Popular card or a LibriVox search
result (see [tabs](tabs.md)). Describes one book, starts its download, and becomes a **Play** button
once the book is in the library. The only way to add a LibriVox book.

## Sub-features

- **load:** `.task` calls `client.details(for:)` (archive.org item metadata, plus chapter titles from
  the LibriVox API when the item matches one). While loading it shows a `ProgressView`; on failure
  *"Couldn't load this book."* and a **Retry** button (`detail.retry`) that reloads.
- **header:** cover (`AsyncImageView`, see *cover-loading* below), title, author, then
  `<length> · <N> chapters · <language>` (length as `2h 58m`, or `58m` under an hour; the count
  is a plural variant, `1 chapter` / `1 capítulo`, `0 capítulos` in pt-BR, #180) and the
  whole-book download size (`ByteSize.text`, summed over the chapter files). The language name and
  the size follow the **in-app** language (`AbbayBundle.locale`), not the device's: English on a
  Portuguese device reads "English" and "29.7 MB", not "inglês" and "29,7 MB" (#152, #166). The
  large-download alert's size uses the same text. With `-stubLibriVox` the size is 29,670,000
  bytes ("29.7 MB" / "29,7 MB"), so the separator shows which locale formatted it.
- **cover-loading:** `AsyncImageView`, shared with the Search tab's cards and results. While the
  cover loads, an `onyx` tile with a light band sweeping across it (`cover.loading`); then the
  image fades in (`cover.loaded`). A failed load (offline, non-2xx, not an image) leaves the `onyx`
  tile with a `book.closed` glyph (`cover.failed`). Covers load through `NetworkProvider`
  (`AsyncImageLoader`) and are kept in memory per URL (`NSCache`, 100 covers), so a cover that
  already loaded, on this page or a Search card, shows at once with no shimmer and no fade.
  Their bytes are also kept on disk (`CoverDiskCache`, `Caches/LibriVoxCovers`, 30 MB, least
  recently used dropped first, file names a SHA-256 of the URL), so after a relaunch a cover
  comes from disk, not the network: a brief `cover.loading`, then `cover.loaded`. Concurrent
  loads of one URL (a Popular card and the page it opens) share one download, so this page can
  open mid-load and finish with the card. Only HTTPS on `librivox.org`, `archive.org` and their
  subdomains is fetched (`CoverHostPolicy`); any other URL fails at once without a request and is
  logged (`Log.covers`, URL private). Reduce Motion: a plain `onyx` tile instead of the sweep,
  and no fade. Leaving the screen stops the view waiting, but the shared download finishes and is
  cached; a failure is retried on the next appearance.
- **description:** three lines, with a **More** button (`detail.more`) that expands it in place. The
  button shows whenever the description is non-empty and collapsed — not only when the text is
  actually truncated.
- **download:** primary **Download** button (`detail.download`). It saves the book (cover fetched
  first), hands it to the download manager, adds it to the Library and **stays on the page**; the
  button becomes **Play**. Tapping it twice while saving is ignored.
- **cellular-warning:** if the book is over 99,000,000 bytes *and* the phone is on a metered network
  (cellular, Personal Hotspot or Low Data Mode, `NetworkPathMonitor.isMetered`), an alert
  *"Large download"* offers **Continue** (`detail.cellular.continue`, cellular allowed for this book)
  and **Wait for Wi-Fi** (`detail.cellular.wait`, unmetered Wi-Fi only; the book still starts and
  shows Waiting). Over the threshold on unmetered Wi-Fi it starts without asking, with cellular *not*
  allowed, so a later move to cellular, a hotspot or Low Data Mode holds it. At or under the threshold it never asks and allows cellular.
  The choice is stored per book (`allowsCellularDownload`). Streaming is unaffected.
- **play:** **Play** (`detail.play`) starts playback and opens the details screen
  ([player](player.md)) through the injected `openPlayer`, i.e. `presentation.open`, the same
  presentation a Library row or the [mini player](mini-player.md) opens. With nothing visible to grow
  from yet it grows up from the bottom strip; collapsing it (`player.close`, or a drag down) lands on
  the mini player, which now shows this book, and returns to the page.
- **already-owned:** a book already in the Library opens with **Play** instead of Download (looked up
  by its `librivox://book/<id>` URL) and is never added twice.
- **download-state:** read from the app-wide `DownloadStateStore` entry for this book, not from a
  `statesPublisher` sink of its own, so the download manager keeps one subscriber
  (`SubscriptionBudgetTests`).
- **chapters:** the shared `ChapterListView` in its stack layout: *Chapter selection* header (*Seleção de capítulos*), one row per
  chapter with scrolling title and duration. While the download is **incomplete** each row also
  shows ✓ / `N%` / *Waiting* / *Failed · Retry* and a thin overall progress bar (`detail.progress`)
  sits under the header; once complete both disappear. A *Wait for Wi-Fi* book held by Low Data
  Mode on Wi-Fi also shows *"Waiting: Low Data Mode is on"* under the bar (`detail.lowDataMode`, see
  [downloads](downloads.md) *low-data-mode-hint*). Rows are not tappable here — Play opens the
  player, which is where chapters are chosen — but a failed chapter's status is a button
  (`detail.chapter.<n>.retry`) that restarts its download. A book with no sections shows the
  list's *No chapters* empty state (`detail.chapters.empty`; unverified by UI test, the stub book
  has a chapter).
- **credit:** footer *"Public domain recording by LibriVox volunteers"*.

## How to get to it (user POV)

Tap **Search** in the tab bar (or *Browse free audiobooks* on the empty library, which switches to
it), then tap a *Popular on LibriVox* card, or type in *Search LibriVox* and tap a result. The page
is pushed on the Search tab's `NavigationStack`. A book that is already in the Library opens here
too, showing **Play**. The Library tab's own search is local only and never leads here.

## Driving it with abbay-ctl

```bash
$B launch -seedLibrary -stubLibriVox          # in-memory catalog, nothing downloads
$B tap root.tab.search
$B tap placeholder:"Search LibriVox"         # the field has no id: found by placeholder (see tabs.md)
$B type "Stub"                                # the only query the stub answers (any query containing "stub")
$B tap search.result.0 && $B wait detail.download
$B tap detail.download && $B wait detail.play # page stays open; Download is gone
$B tap detail.play && $B wait player.transport.play
$B tap player.close                           # or drag its header down
```

**Verified** (`AccessibilityIdentifierTests`): `detail.view` (also from `search.card.0`,
`test_searchTab_showsPopularCards_andOpensDetails`), `detail.download`, `detail.play`
(`test_libriVoxDownload_keepsDetailPageOpenAndShowsPlay`,
`test_playFromDetail_opensPlayer_thenLibraryShowsMiniPlayer`), reached through the Search tab's
`search.result.0`. Play calls the injected `openPlayer`, i.e. `presentation.open`; the page no
longer presents its own player sheet.

**Implemented but unverified** (declared in `AccessibilityID.Detail` and attached in the view, but no
UI test resolves them): `detail.more`, `detail.retry`, `detail.cellular.continue`,
`detail.cellular.wait`, `detail.progress`, `detail.lowDataMode`, `detail.chapter.<n>`,
`detail.chapter.<n>.retry`. The stub
book is 1,000 bytes, so the cellular alert is unreachable by UI; the stub client never fails
`details`, so Retry is too; and the stub download manager reports no state, so `detail.progress` and
the chapter retry never appear (see [downloads](downloads.md)).
The decisions behind them are unit-tested: `CellularDownloadPolicyTests`, `NetworkPathSnapshotTests`,
`LibriVoxDetailViewModelTests`, `ChapterListViewTests`.

All three cover states are verified by `CoverUITests`:

- `cover.failed`: the stub's cover is a `/dev/null` file URL, which the host allowlist refuses
  (`test_detailCover_thatFailsToLoad_showsTheFallback`).
- `cover.loading` then `cover.loaded`: with `-stubCovers` the stub's cover is
  `https://archive.org/services/img/ui-test-stub`, answered after 12 s by `UITestCoverNetwork`, so
  the page opens mid-load (`test_detailCover_showsLoading_thenLoaded`).
- disk cache across a relaunch: a `-stubCovers` launch stores the cover, then a
  `-stubCovers -stubCoversOffline` launch, whose cover requests all fail, still shows `cover.loaded`
  (`test_detailCover_afterARelaunch_isServedFromDisk`).
- Reduce Motion: two frames of the loading cover 0.5 s apart differ normally
  (`test_loadingCover_shimmers`) and are identical with `-forceReduceMotion`
  (`test_loadingCover_withReduceMotion_isStatic`). All five pass on iOS 26.4, 18.5 and 17.5.
  `AsyncImageView` reads Reduce Motion through `@ReduceMotion`, so the override reaches this pushed
  page on iOS 17/18 too; an environment override at the root didn't (#185). The test always keeps
  the two frames it compared as attachments.

```bash
$B launch -seedLibrary -stubLibriVox -stubCovers   # cover loads for 12 s, then a green square
$B tap root.tab.search && $B tap search.card.0
$B wait cover.loading && $B wait cover.loaded
$B launch -seedLibrary -stubLibriVox -stubCovers -stubCoversOffline   # only disk can answer
$B tap root.tab.search && $B tap search.card.0 && $B wait cover.loaded
```

Shared downloads, the disk cache's size bound and the allowlist's host matching are unit-tested in
`AsyncImageLoaderTests` and `CoverDiskCacheTests`. The Popular card's and search row's covers have
no id of their own (the card/row button's id covers them), so the details page is where cover
states are read.

**Not addressable:** there is no identifier on the title, author, size or credit text.

## Gotchas

- **Stub limits.** `UITestLibriVoxClient` serves one book (`ui-test-stub`, one 60 s chapter whose
  `/dev/null/...` URLs are not real files) and `UITestDownloadManager` downloads nothing. Playing it
  therefore opens the details screen and the mini player appears, but no audio plays. Everything about
  real search results, real sizes, real covers and real downloads is **unreachable by UI automation**.
  `-stubCovers` gives the stub a cover that loads (a generated green square), from its own disk
  cache (`Caches/UITestCovers`, emptied at each `-stubCovers` launch unless `-stubCoversOffline`).
- **The page is state-held by the Search tab, not by the result row.** `SearchTab` (in
  `AppRootView.swift`) keeps the opened book in `openedBook` and pushes it with
  `navigationDestination(item:)`, so a result row changing under it can't pop the page before
  **Play** appears (regression-tested by `test_libriVoxDownload_keepsDetailPageOpenAndShowsPlay`).
- **`detail.view` is set on the page's outer view** while its children carry their own ids. The UI
  tests resolve both together today, but do not assume the container id is stable evidence that a
  child exists — assert on the leaf you need.
- Chapter rows are `accessibilityElement(children: .combine)`, so a row's title, status and duration
  read as one element whose label is their concatenation.
- **More** is not conditional on truncation, so a short description still shows it and tapping it
  changes nothing visible.
- Details are cached for 7 days and fall back to the cache when a refresh fails, so a page can show
  data older than the catalog. Chapter titles fall back to archive.org's file-derived titles when the
  LibriVox lookup finds no match.
- Network is real in the default configuration. A driver that does not pass `-stubLibriVox` talks to
  librivox.org and archive.org and is subject to their availability.
