# LibriVox details page

`LibriVoxDetailView` — the page pushed from a LibriVox search result. Describes one book, starts its
download, and becomes a **Play** button once the book is in the library. The only way to add a
LibriVox book.

## Sub-features

- **load:** `.task` calls `client.details(for:)` (archive.org item metadata, plus chapter titles from
  the LibriVox API when the item matches one). While loading it shows a `ProgressView`; on failure
  *"Couldn't load this book."* and a **Retry** button (`detail.retry`) that reloads.
- **header:** cover (`AsyncImage`, onyx placeholder), title, author, then
  `<length> · <N> chapters · <language>` (length as `2h 58m`, or `58m` under an hour) and the
  whole-book download size (`ByteCountFormatter`, summed over the chapter files).
- **description:** three lines, with a **More** button (`detail.more`) that expands it in place. The
  button shows whenever the description is non-empty and collapsed — not only when the text is
  actually truncated.
- **download:** primary **Download** button (`detail.download`). It saves the book (cover fetched
  first), hands it to the download manager, adds it to the Library and **stays on the page**; the
  button becomes **Play**. Tapping it twice while saving is ignored.
- **cellular-warning:** if the book is over 99,000,000 bytes *and* the phone is on cellular, an alert
  *"Large download"* offers **Continue** (`detail.cellular.continue`, cellular allowed for this book)
  and **Wait for Wi-Fi** (`detail.cellular.wait`, Wi-Fi only; the book still starts and shows
  Waiting). Over the threshold on Wi-Fi it starts without asking, with cellular *not* allowed, so a
  later move to cellular pauses it. At or under the threshold it never asks and allows cellular.
  The choice is stored per book (`allowsCellularDownload`). Streaming is unaffected.
- **play:** **Play** (`detail.play`) starts playback and presents the same [player](player.md) sheet a
  Library row opens. Dismissing the sheet returns to the page.
- **already-owned:** a book already in the Library opens with **Play** instead of Download (looked up
  by its `librivox://book/<id>` URL) and is never added twice.
- **chapters:** the shared `ChapterListView` in its stack layout: *Chapters* header, one row per
  chapter with scrolling title and duration. While the download is **incomplete** each row also
  shows ✓ / `N%` / *Waiting* and a thin overall progress bar (`detail.progress`) sits under the
  header; once complete both disappear. Rows are not tappable here — Play opens the player, which is
  where chapters are chosen.
- **credit:** footer *"Public domain recording by LibriVox volunteers"*.

## How to get to it (user POV)

Library → ＋ → *Browse LibriVox* (or *Browse free audiobooks* on the empty library), or type in the
search field → tap a result under **On LibriVox** / **Popular on LibriVox**. A result already in the
Library appears under *In your library* instead and opens the player, not this page.

## Driving it with abbay-ctl

```bash
$B launch --seed-library --stub-librivox      # -stubLibriVox: in-memory catalog, nothing downloads
$B tap root.tab.search
$B tap searchfield && $B type "Stub"          # the only query the stub answers (any query containing "stub")
$B tap search.result.0 && $B wait detail.download
$B tap detail.download && $B wait detail.play # page stays open; Download is gone
$B tap detail.play && $B wait player.transport.play
$B tap player.close                           # or drag its header down
```

**Verified** (`AccessibilityIdentifierTests`): `detail.view`, `detail.download`, `detail.play`
(`test_libriVoxDownload_keepsDetailPageOpenAndShowsPlay`,
`test_playFromDetail_opensPlayer_thenLibraryShowsFloatingPlayer`), reached through the Search tab's
`search.result.0`. Play calls the injected `openPlayer`, i.e. `presentation.open`; the page no
longer presents its own player sheet.

**Implemented but unverified** (declared in `AccessibilityID.Detail` and attached in the view, but no
UI test resolves them): `detail.more`, `detail.retry`, `detail.cellular.continue`,
`detail.cellular.wait`, `detail.progress`, `detail.chapter.<n>`. The stub book is 1,000 bytes, so the
cellular alert is unreachable by UI; the stub client never fails `details`, so Retry is too; and the
stub download manager reports no state, so `detail.progress` never appears (see [downloads](downloads.md)).
The decisions behind them are unit-tested: `CellularDownloadPolicyTests`,
`LibriVoxDetailViewModelTests`, `ChapterListViewTests`.

**Not addressable:** there is no identifier on the cover, title, author, size or credit text.

## Gotchas

- **Stub limits.** `UITestLibriVoxClient` serves one book (`ui-test-stub`, one 60 s chapter whose
  `/dev/null/...` URLs are not real files) and `UITestDownloadManager` downloads nothing. Playing it
  therefore opens the player and the floating player appears, but no audio plays. Everything about
  real search results, real sizes, real covers and real downloads is **unreachable by UI automation**.
- **The page is state-held by the Library, not by the result row.** `MediaListView` keeps the opened
  book in `openedBook` because adding the book removes its search row, which would pop a row-owned
  link before **Play** could appear (regression-tested).
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
