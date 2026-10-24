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
  floating player disappears; deleting the book the details screen shows closes it.
- **toolbar:** a **＋** `Menu` (`library.toolbar.add`) with only **Import file**
  (`library.menu.import`), plus the dead `gearshape` button (`library.toolbar.settings`).
- **floating-player:** when a book is loaded (`PlaybackState.loadedBook`),
  [floating-player](floating-player.md) sits at the bottom of the Library tab, above the tab bar;
  tapping it calls `presentation.open`. Interim: the docked bar replaces it.
- **live-selection:** `selectedAudio` is `PlaybackState.loadedBook`, so playback started anywhere
  (Siri, CarPlay) shows the floating player. On each book switch the root hands the new book to
  `loadedBookChanged(to:)`, which re-reads the outgoing and incoming books from storage.

## How to get to it (user POV)

The first tab on launch (`root.tab.library`).

## Driving it with abbay-ctl

```bash
$B launch --seed-library --stub-librivox
$B wait library.list
$B tap library.row.0.title                   # → player (slides up); close with player.close
$B tap library.toolbar.add && $B tap library.menu.import   # → document picker
$B tap root.tab.search                       # → Search tab
```

**Verified** (`AccessibilityIdentifierTests`): `library.list`, `library.empty`,
`library.empty.browse` (opens the Search tab), `library.empty.import`, `library.toolbar.add`,
`library.menu.import`, `library.toolbar.settings`, `library.search.noResults`,
`library.row.<n>.*`, and `library.floatingPlayer` (after Play on the stub book's details page).

**Not addressable:** `library.row.<n>` on its own (leaf-only rule). The search field has no
identifier: find it by placeholder (*Search your library*).

## Gotchas

- **Settings is a dead button** (issue #58).
- **`library.floatingPlayer` sits on a container**, overwriting identifiers inside it.
- **Row taps use `onTapGesture`.** Rows are keyed by `\.url`.
- `deleteAudio` mutates `audioList` directly rather than reloading; the delete use case has no error
  path.
- Row order is whatever `LoadAllAudiosUseCase` returns; there is no explicit sort.
