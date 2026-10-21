# Library

`MediaListView` — the root screen. The list of imported audiobooks, the empty state, swipe-to-delete,
and the toolbar.

## Sub-features

- **list:** `List` over `model.audioList`, keyed by `\.url`, one [media-row](media-row.md) per book.
  Plain list style, dark scheme forced.
- **empty-state:** when `audioList.isEmpty` (and the user is not browsing) the list is replaced by a
  `folder.badge.questionmark` glyph, *"So empty..."* (`library.empty`), a primary malachite
  **Browse free audiobooks** button (`library.empty.browse`) and a secondary onyx **Import a file**
  button (`library.empty.import`, opens the document picker). No search bar in this state.
- **search:** with books, `.searchable` adds a search field under the title (no accessibility
  identifier is possible on it; drive it with `app.searchFields.firstMatch`). While the field is
  active or a query is typed the list is replaced by two sections: **In your library** (local
  matches on title or artist, case/diacritic-insensitive, rows `library.search.local.<n>.*`, with a
  *Downloaded* tag on LibriVox books) and **On LibriVox** (debounced remote results,
  `library.remote.<n>`; tapping pushes a placeholder until the details page lands). An empty
  query shows **Popular on LibriVox**. Offline/failed remote states render a message
  (`library.search.message`). No matches anywhere shows `library.search.noResults`, distinct from
  `library.empty`. Remote books already in the library are left out of the remote section.
- **row-tap:** sets `tappedAudio` and presents [player](player.md) as a sheet.
- **delete:** trailing swipe, full-swipe enabled, destructive `Delete` button. Removes from Core Data
  via `DeleteAudioUseCase`, drops it from `audioList`, rewrites the snapshot.
- **toolbar:** a **＋** `Menu` (`library.toolbar.add`) with **Browse LibriVox**
  (`library.menu.browse`, focuses the search and shows popular books) and **Import file**
  (`library.menu.import`, the document picker), plus a `gearshape` `Button`
  (`library.toolbar.settings`) that still does nothing. All are real SwiftUI controls, so the
  system sizes them in the glass toolbar capsule.
- **floating-player:** when `model.selectedAudio` is non-nil, [floating-player](floating-player.md)
  is overlaid at the bottom; tapping it opens the full player on that book.
- **live-selection:** the view model subscribes to the player's URL publisher, so playback started
  anywhere (Siri, CarPlay) updates `selectedAudio` and the floating player appears.

## How to get to it (user POV)

It is the first and only screen on launch. Everything else is reached from here.

## Driving it with abbay-ctl

```bash
$B launch --seed-library                     # -seedLibrary (add -stubLibriVox to keep search off the network)
$B wait library.list
$B snapshot                                  # expect library.row.<n> per book
$B tap library.row.0                         # → player sheet
$B tap library.toolbar.add && $B tap library.menu.import   # → document picker
$B swipe library.row.0 left && $B tap library.row.0.delete
$B wait library.empty                        # after deleting the last book
$B tap library.floatingPlayer                # → player sheet on the playing book
$B appgroup get abbay.librarySnapshot.v1     # assert the delete rewrote the snapshot
```

**Verified** (`AccessibilityIdentifierTests`): `library.list`, `library.empty`,
`library.empty.browse`, `library.empty.import`, `library.toolbar.add`, `library.menu.browse`,
`library.menu.import`, `library.toolbar.settings`, `library.search.noResults`,
`library.search.local.<n>`.

**Not addressable:** `library.row.<n>` on its own — a container identifier would overwrite every
leaf inside the row, so rows are reached through `library.row.<n>.title` (see
[media-row](media-row.md)). There is no `library.root`; use `library.list` or `library.empty` as
the "screen is up" signal depending on the state you expect.

**Not implemented:** `library.row.<n>.delete` (the delete is a swipe action, not a persistent
element) and `library.floatingPlayer` is declared but unverified — the floating player only
appears once audio is genuinely playing, which the synthetic seed cannot do.

## Gotchas

- **Settings is a dead button.** `gearshape` is a `Button` with an empty action (issue #58); it
  renders as tappable but does nothing. Wire it up or remove it before submission.
- **Search tests must not hit the network.** Launch with `-stubLibriVox` (`LaunchArgument`), which
  swaps in a client that returns no LibriVox books; assert only local filtering.
- Rows are keyed by `\.url`. Two imports resolving to the same URL collapse to one row;
  `importAudio` already de-duplicates on `url`.
- `deleteAudio` mutates `audioList` directly rather than reloading, so the list and Core Data can
  drift if the delete use case fails — it has no error path.
- The empty state is *not* the same as the CarPlay empty state, which does not exist at all (#95).
- Row order is whatever `LoadAllAudiosUseCase` returns; there is no explicit sort.
