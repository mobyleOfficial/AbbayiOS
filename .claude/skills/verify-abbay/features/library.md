# Library

`MediaListView` — the **Library tab** of `AppRootView` (see [app-shell](app-shell.md)). The list of
audiobooks (imported or LibriVox), the empty state, swipe-to-delete, a local-only search and the
toolbar. The root owns the model (`MediaListViewModel`) and the tab's `NavigationStack`. LibriVox
search and the [details page](librivox-details.md) live in the Search tab.

## Sub-features

- **list:** `List` over `LibraryFilter.filter(model.audioList, query:)`, keyed by `\.url`, one
  [media-row](media-row.md) per book (`library.row.<n>.*`, positional within the filtered list).
- **empty-state:** when `audioList.isEmpty`: a glyph, *"So empty..."* (`library.empty`), a primary
  **Browse free audiobooks** button (`library.empty.browse`, switches to the Search tab) and a
  secondary **Import a file** button (`library.empty.import`). No search field in this state.
- **search:** with books, `.searchable(placement: .navigationBarDrawer(displayMode: .always))`, prompt
  *Search your library*, always at the top. Filters title or author, ignoring case and diacritics;
  never hits the network. While a query is typed, a fully downloaded LibriVox book shows a
  *Downloaded* tag. No matches shows `library.search.noResults`.
- **row-tap:** `presentation.open(book)` — the one player presentation (see [player](player.md)).
- **delete:** trailing swipe. Removes from Core Data, drops it from `audioList`, rewrites the
  snapshot. Deleting the loaded book unloads it from the player (`PlaybackCenter.unload()`), so the
  mini player disappears; deleting the book the details screen shows closes it.
- **toolbar:** a **＋** `Menu` (`library.toolbar.add`) with only **Import file**
  (`library.menu.import`), plus the dead `gearshape` button (`library.toolbar.settings`).
- **mini-player:** when a book is loaded (`PlaybackState.loadedBook`), the
  [mini player](mini-player.md) docks above the tab bar on both tabs, and the list's last row ends
  above it (`test_lastRow_isNotCoveredByMiniPlayer`).
- **live-selection:** the loaded book is `PlaybackState.loadedBook`, so playback started anywhere
  (Siri, CarPlay) shows the mini player and the row's playing state. On each book switch the root hands the new book to
  `loadedBookChanged(to:)`, which re-reads the outgoing and incoming books from storage.

## How to get to it (user POV)

The first tab on launch (`root.tab.library`). See [tabs](tabs.md) for the tab bar and the Search tab.

## Driving it with abbay-ctl

```bash
$B launch --seed-library --stub-librivox
$B wait library.list
$B tap library.row.0.title                   # → details screen (grows up); close with player.close
$B tap library.row.0.play && $B wait miniPlayer.bar        # loads the seeded book (no audio)
$B tap library.toolbar.add && $B tap library.menu.import   # → document picker
$B swipe library.row.0 left                  # trailing Delete action (no identifier)
$B wait library.empty                        # after deleting the last book
$B appgroup get abbay.librarySnapshot.v1     # assert the delete rewrote the snapshot
$B tap root.tab.search                       # → Search tab
```

**Verified** (`AccessibilityIdentifierTests`): `library.list`, `library.empty`,
`library.empty.browse` (opens the Search tab), `library.empty.import`, `library.toolbar.add`,
`library.menu.import`, `library.toolbar.settings`, `library.search.noResults`,
`library.row.<n>.{artwork,title,detail,play}` (see [media-row](media-row.md)).

**Not addressable:** `library.row.<n>` on its own (leaf-only rule). The search field has no
identifier: `.searchable` exposes no way to set one, so find it by placeholder (*Search your library*).
Typing a title hides the other rows (`test_search_filtersLocalRows`); no matches shows
`library.search.noResults`, never `library.empty` (`test_search_withoutMatches_showsNoResultsState`). There is no `library.root`; use
`library.list` or `library.empty` as the "screen is up" signal depending on the state you expect.

**Not implemented:** `library.row.<n>.delete` — the delete is a swipe action, not a persistent
element. `library.floatingPlayer` and `library.menu.browse` are gone (the floating player was
replaced by the mini player; browsing LibriVox is the Search tab).

**Seeded books can't play audio.** Their models carry no playable file. Pressing a seeded row's
play button still makes the player announce the book, so the mini player and the row's loaded
state appear (that is how `MiniPlayerUITests` loads one), but the clock never moves and nothing is
heard. Anything needing real playback — chapter taps (gated on playing), time advancing, the end
of a chapter — needs a genuinely playable import.

## Gotchas

- **Settings is a dead button.** `gearshape` is a `Button` with an empty action (issue #58); it
  renders as tappable but does nothing. Deliberately kept: the settings screen lands with #58, not
  with the search work (#112).
- **Search and stub tests need `-stubLibriVox`.** The Library's own search is local, but the Search
  tab, the *Browse free audiobooks* button's destination and the stub-book flows all talk to
  archive.org and librivox.org without it. With it, LibriVox answers from memory
  (`UITestLibriVoxClient`: Popular is the one stub book, found by any query containing "stub") and
  downloads do nothing.
- **The empty state has no search field** (`test_emptyLibrary_hasNoSearchField`).
- **The CarPlay library has no empty state at all** (#95, still open; see [carplay](carplay.md)),
  unlike this one.
- **Row taps use `onTapGesture`.** Rows are keyed by `\.url`; two imports resolving to the same
  URL collapse to one row (`importAudio` de-duplicates on `url`).
- `deleteAudio` mutates `audioList` directly rather than reloading; the delete use case has no error
  path.
- Row order is whatever `LoadAllAudiosUseCase` returns; there is no explicit sort.
