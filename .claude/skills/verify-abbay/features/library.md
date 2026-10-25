# Library

`MediaListView` — the **Library tab** of `AppRootView` (see [app-shell](app-shell.md)), "Library B"
since #166 G3: a Continue card for the last played book above a three-column grid of covers
(imported or LibriVox), the empty state, context-menu delete, a local-only search and the toolbar.
It paints no background of its own, so the scroll edge effect works under the bars. The root owns the model (`MediaListViewModel`) and the tab's `NavigationStack`. LibriVox
search and the [details page](librivox-details.md) live in the Search tab.

## Sub-features

- **grid:** a `ScrollView` (`library.list`) with an *All books* header and a `LazyVGrid` over
  `LibraryFilter.filter(model.audioList, query:)`, keyed by `\.url`: three flexible columns (two
  from the *xLarge* text size up, so titles never truncate), one [media-row](media-row.md) cell per book
  (`library.row.<n>.*`, positional within the filtered grid). Order unchanged (repository order).
- **continue-card:** above the grid, under a *Continue* header, while the search is empty:
  `ContinueCard.book(in:lastPlayedURL:)` picks the last played book (`LastPlayedStore`) if it is
  still in the library and not finished (within 30 s of the end), else there is no card. Cover
  (94 pt, scaled), title (`library.continue`, the tap handle: opens the player),
  *Chapter 3 · 28 min left* (`library.continue.detail`, the mini player's subtitle), a malachite
  **Resume** / **Pause** capsule (`library.continue.resume`, plays or pauses without opening) and the
  book's progress. The fill is the cover's tint (`CoverTint`) shading to black; content, not glass.
  Live (reads `PlaybackClock`) only while its book is loaded. `-seedLastPlayed` makes *Seeded
  Chaptered Book* (150 s in) last played; seeding without it clears last played.
- **empty-state:** when `audioList.isEmpty`: a `ContentUnavailableView` with `books.vertical`,
  *"So empty..."* (`library.empty`), a line about LibriVox and importing, a glass-prominent
  **Browse free audiobooks** capsule (`library.empty.browse`, switches to the Search tab) and a glass
  **Import a file** capsule (`library.empty.import`). No search field in this state.
- **search:** with books, `.searchable(placement: .navigationBarDrawer(displayMode: .always))`, prompt
  *Search your library*, always at the top. Filters title or author, ignoring case and diacritics;
  never hits the network. While a query is typed the Continue card and the headers hide, results
  show in the same grid, and a fully downloaded LibriVox book shows a *Downloaded* badge on its
  cover. No matches shows a search `ContentUnavailableView` (*No results for “…”*, *Check the
  spelling or try a new search.*) whose title is `library.search.noResults`; it is built from our
  strings, not `ContentUnavailableView.search`, so it follows the in-app language.
- **cell-tap:** `presentation.open(book)` — the one player presentation (see [player](player.md)).
  Play / Pause is in the cell's context menu (there is no play button on a cell).
- **delete:** the cell's context menu, *Delete* (`library.row.<n>.delete`; it replaced the trailing
  swipe). Removes from Core Data, drops it from `audioList`, rewrites the
  snapshot. Deleting the loaded book unloads it from the player (`PlaybackCenter.unload()`), so the
  mini player disappears; deleting the book the details screen shows closes it.
- **toolbar:** a **＋** `Menu` (`library.toolbar.add`) with only **Import file**
  (`library.menu.import`), plus the `gearshape` button (`library.toolbar.settings`, label
  *Settings*), which opens the [Settings](settings.md) sheet.
- **mini-player:** when a book is loaded (`PlaybackState.loadedBook`), the
  [mini player](mini-player.md) docks above the tab bar on both tabs, and the grid's last cell ends
  above it (`test_lastCell_isNotCoveredByMiniPlayer`).
- **live-selection:** the loaded book is `PlaybackState.loadedBook`, so playback started anywhere
  (Siri, CarPlay) shows the mini player and the row's playing state. On each book switch the root hands the new book to
  `loadedBookChanged(to:)`, which re-reads the outgoing and incoming books from storage.

## How to get to it (user POV)

The first tab on launch (`root.tab.library`). See [tabs](tabs.md) for the tab bar and the Search tab.

## Driving it with abbay-ctl

```bash
$B launch -seedLibrary -stubLibriVox
$B wait library.list
$B tap library.row.0.title                   # → details screen (grows up); close with player.close
$B press library.row.0.title && $B tap library.row.0.play && $B wait miniPlayer.bar   # plays from the menu
$B launch -seedLibrary -seedLastPlayed -seedArtwork      # Continue card for Seeded Chaptered Book, with covers
$B tap library.continue.resume && $B wait miniPlayer.bar
$B tap library.toolbar.add && $B tap library.menu.import   # → document picker
$B press library.row.0.title && $B tap library.row.0.delete
$B wait library.empty                        # after deleting the last book
$B appgroup get abbay.librarySnapshot.v1     # assert the delete rewrote the snapshot
$B tap root.tab.search                       # → Search tab
```

**Verified** (`AccessibilityIdentifierTests`): `library.list`, `library.empty`,
`library.empty.browse` (opens the Search tab), `library.empty.import`, `library.toolbar.add`,
`library.menu.import`, `library.toolbar.settings`, `library.search.noResults`,
`library.row.<n>.{artwork,title,detail}` and, with the menu open, `.{play,delete}` (see
[media-row](media-row.md)). `LibraryGridUITests`: the Continue card (`library.continue`,
`.detail`, `.resume` flipping to *Pause*, tap opens the player, absent without
`-seedLastPlayed`, hidden while searching) and delete from the menu.

**Not addressable:** `library.row.<n>` on its own (leaf-only rule). The search field has no
identifier: `.searchable` exposes no way to set one, so find it by placeholder (*Search your library*).
Typing a title hides the other rows (`test_search_filtersLocalRows`); no matches shows
`library.search.noResults`, never `library.empty` (`test_search_withoutMatches_showsNoResultsState`). There is no `library.root`; use
`library.list` or `library.empty` as the "screen is up" signal depending on the state you expect.

**Not addressable:** `library.row.<n>.{play,delete}` while the menu is closed. **Gone:**
`library.floatingPlayer` and `library.menu.browse` are gone (the floating player was
replaced by the mini player; browsing LibriVox is the Search tab).

**Seeded books play real audio** (#147). Each is a hard link to the Debug-only
`Christmastide.m4b` fixture, so Play in a seeded cell's menu plays it: the mini player and
the cell's loaded state appear (that is how `MiniPlayerUITests` loads one) and the clock moves. The
seeds' chapters and durations are their own, not the file's (14 min). No file behind:
*Seeded Missing Book* (`-seedMissingFile`, the moved-file banner) and the `-seedTimeLeftEdges`
books, whose clocks must stay put. Delete and `-resetLibrary` find a book's row by the URL it was
stored under, so they work after a reinstall moved the bundle (#176). Since #186 that URL is the
book's only identity (rows, the loaded-row state, last played, Siri, speeds, CarPlay); only the
player opens the file where its bookmark resolves now (see [import](import.md) *identity*).

## Gotchas

- **The gear's sheet is presented by the root**, not by this view (`onSettings`), so a language
  switch, which rebuilds the tabs, doesn't dismiss it.
- **Search and stub tests need `-stubLibriVox`.** The Library's own search is local, but the Search
  tab, the *Browse free audiobooks* button's destination and the stub-book flows all talk to
  archive.org and librivox.org without it. With it, LibriVox answers from memory
  (`UITestLibriVoxClient`: Popular is the one stub book, found by any query containing "stub") and
  downloads do nothing.
- **The empty state has no search field** (`test_emptyLibrary_hasNoSearchField`).
- **The CarPlay library has no empty state at all** (#95, still open; see [carplay](carplay.md)),
  unlike this one.
- **Cell taps use `onTapGesture`.** Cells are keyed by `\.url` (the row's URL); two imports of the
  same URL collapse to one row (`importAudio` replaces the row with the same `url`). Importing a
  moved file again from its new place relinks the book it already is and replaces its row, so no
  second book appears (#196, see [import](import.md) *re-import of a moved book*).
- `deleteAudio` mutates `audioList` directly rather than reloading; the delete use case has no error
  path.
- Row order is whatever `LoadAllAudiosUseCase` returns; there is no explicit sort.
