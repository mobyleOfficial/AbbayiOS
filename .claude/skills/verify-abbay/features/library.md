# Library

`MediaListView` — the root screen. The list of audiobooks (imported or LibriVox), the empty state,
swipe-to-delete, the combined library/LibriVox search and the toolbar. It owns the `NavigationStack`
that pushes the [LibriVox details page](librivox-details.md).

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
  `library.remote.<n>`). A remote row is a `Button` that sets `openedBook`, which pushes the
  [LibriVox details page](librivox-details.md); a local row opens the [player](player.md) sheet.
  Search runs on archive.org scoped to the LibriVox collection: every typed word must match the
  title or the author, and each word matches as a prefix (so type-ahead and "alice carroll" work).
  Remote results are debounced 400 ms (50 ms under `-stubLibriVox`) and skipped while offline.
  An empty query shows **Popular on LibriVox** (archive.org's LibriVox collection by downloads,
  30 books, cached 24 h, served from the cache even offline and refreshed in the background);
  clearing the query restores the last popular list. When nothing can be shown, the remote section
  renders a message (`library.search.message`): *offline* or *could not reach LibriVox*. No matches
  anywhere shows `library.search.noResults`, distinct from `library.empty`. Remote books already in
  the library are left out of the remote section.
- **row-tap:** sets `tappedAudio` and presents [player](player.md) as a sheet.
- **delete:** trailing swipe, full-swipe enabled, destructive `Delete` button. Removes from Core Data
  via `DeleteAudioUseCase`, drops it from `audioList`, rewrites the snapshot.
- **toolbar:** a **＋** `Menu` (`library.toolbar.add`) with **Browse LibriVox**
  (`library.menu.browse`, focuses the search and shows popular books) and **Import file**
  (`library.menu.import`, the document picker), plus a `gearshape` `Button`
  (`library.toolbar.settings`) that still does nothing. All are real SwiftUI controls, so the
  system sizes them in the glass toolbar capsule.
- **floating-player:** when `model.selectedAudio` is non-nil, [floating-player](floating-player.md)
  is overlaid at the bottom — over the list **and over search results** — and tapping it opens the
  full player on that book.
- **download-state:** a LibriVox book still downloading shows a ring on its row
  ([media-row](media-row.md), [downloads](downloads.md)); the list observes the download manager so
  *In your library* rows can show the *Downloaded* tag.
- **add-from-details:** a book added on the details page is appended to `audioList` (and the snapshot
  and Siri parameters refreshed) while the page is still open, so it appears in the list and in
  *In your library* behind it.
- **live-selection:** the view model subscribes to the player's URL publisher, so playback started
  anywhere (Siri, CarPlay) updates `selectedAudio` and the floating player appears.

## How to get to it (user POV)

It is the first and only screen on launch. Everything else is reached from here.

## Driving it with abbay-ctl

```bash
$B launch --seed-library --stub-librivox     # -seedLibrary -stubLibriVox (keeps search off the network)
$B wait library.list
$B snapshot                                  # expect library.row.<n> per book
$B tap library.row.0                         # → player sheet
$B tap library.toolbar.add && $B tap library.menu.import   # → document picker
$B swipe library.row.0 left && $B tap library.row.0.delete
$B wait library.empty                        # after deleting the last book
$B tap library.floatingPlayer                # → player sheet on the playing book (needs real playback, or the stub book's Play)
$B tap library.toolbar.add && $B tap library.menu.browse   # → search focused, Popular on LibriVox
$B tap library.remote.0                      # → LibriVox details page
$B appgroup get abbay.librarySnapshot.v1     # assert the delete rewrote the snapshot
```

**Verified** (`AccessibilityIdentifierTests`): `library.list`, `library.empty`,
`library.empty.browse`, `library.empty.import`, `library.toolbar.add`, `library.menu.browse`,
`library.menu.import`, `library.toolbar.settings`, `library.search.noResults`,
`library.search.local.<n>.title`, `library.remote.<n>` (the stub book, as `library.remote.0`) and
`library.floatingPlayer` (after Play on the stub book's details page, back in search).

**Not addressable:** `library.row.<n>` on its own — a container identifier would overwrite every
leaf inside the row, so rows are reached through `library.row.<n>.title` (see
[media-row](media-row.md)). There is no `library.root`; use `library.list` or `library.empty` as
the "screen is up" signal depending on the state you expect.

**Implemented but unverified:** `library.search.message` (offline / failed remote text; the stub
never errors and tests do not take the network offline). Popular on LibriVox is also unproven by UI:
the stub's `popular()` is empty.

**Not implemented:** `library.row.<n>.delete` — the delete is a swipe action, not a persistent
element.

**Seeded books cannot play.** `library.floatingPlayer` is only reached in tests via the stub LibriVox
book's Play, which sets the player's URL without real audio. Floating-player presence from a seeded
book still needs genuinely playing audio.

## Gotchas

- **Settings is a dead button.** `gearshape` is a `Button` with an empty action (issue #58); it
  renders as tappable but does nothing. Wire it up or remove it before submission.
- **Search tests must not hit the network.** Launch with `-stubLibriVox` (`LaunchArgument`), which
  swaps in an in-memory client (empty Popular; one book, found only by a query containing "stub")
  and a download manager that downloads nothing. Without it the app talks to archive.org and
  librivox.org.
- **The search field has no identifier.** Drive it with `app.searchFields.firstMatch`. Browse from
  the ＋ menu or empty state presents it after a one-tick delay, because the field only exists once
  the content switches to its searchable form; wait for it.
- **The empty state has no search field** (`test_emptyLibrary_hasNoSearchField`), but *Browse free
  audiobooks* switches to the searchable form (Popular on LibriVox, no *In your library* section)
  and the empty state returns when the search is dismissed while the library is still empty.
- **`library.floatingPlayer` sits on a container.** It is applied to the whole floating player, which
  by the rule in the [README](README.md) overwrites any identifier inside it. Adding the planned
  `library.floatingPlayer.*` leaves needs this one moved off the container.
- **Row taps use `onTapGesture`**, in both the list and search results; remote rows are `Button`s.
- Rows are keyed by `\.url`. Two imports resolving to the same URL collapse to one row;
  `importAudio` already de-duplicates on `url`.
- `deleteAudio` mutates `audioList` directly rather than reloading, so the list and Core Data can
  drift if the delete use case fails — it has no error path.
- The empty state is *not* the same as the CarPlay empty state, which does not exist at all (#95).
- Row order is whatever `LoadAllAudiosUseCase` returns; there is no explicit sort.
