# Library

`MediaListView` — the root screen. The list of imported audiobooks, the empty state, swipe-to-delete,
and the toolbar.

## Sub-features

- **list:** `List` over `model.audioList`, keyed by `\.url`, one [media-row](media-row.md) per book.
  Plain list style, dark scheme forced.
- **empty-state:** when `audioList.isEmpty` the list is replaced by a `folder.badge.questionmark`
  glyph and the string *"So empty..."* (`Localizable.emptyLibraryTitle`). No import affordance is
  offered here — the user has to find the toolbar button.
- **row-tap:** sets `tappedAudio` and presents [player](player.md) as a sheet.
- **delete:** trailing swipe, full-swipe enabled, destructive `Delete` button. Removes from Core Data
  via `DeleteAudioUseCase`, drops it from `audioList`, rewrites the snapshot.
- **toolbar:** three `IconButtonView`s — `magnifyingglass`, `plus.rectangle.on.folder`, `gearshape`.
  **Only the middle one does anything.**
- **floating-player:** when `model.selectedAudio` is non-nil, [floating-player](floating-player.md)
  is overlaid at the bottom; tapping it opens the full player on that book.
- **live-selection:** the view model subscribes to the player's URL publisher, so playback started
  anywhere (Siri, CarPlay) updates `selectedAudio` and the floating player appears.

## How to get to it (user POV)

It is the first and only screen on launch. Everything else is reached from here.

## Driving it with abbay-ctl

```bash
$B launch --seed-library
$B wait library.root
$B snapshot                                  # expect library.row.<n> per book
$B tap library.row.0                         # → player sheet
$B tap library.toolbar.import                # → document picker
$B swipe library.row.0 left && $B tap library.row.0.delete
$B wait library.empty                        # after deleting the last book
$B tap library.floatingPlayer                # → player sheet on the playing book
$B appgroup get abbay.librarySnapshot.v1     # assert the delete rewrote the snapshot
```

Identifiers to add: `library.root`, `library.empty`, `library.row.<n>`, `library.row.<n>.delete`,
`library.toolbar.search`, `library.toolbar.import`, `library.toolbar.settings`,
`library.floatingPlayer`.

## Gotchas

- **Two of the three toolbar buttons are dead.** `IconButtonView(systemName: "magnifyingglass")` and
  `IconButtonView(systemName: "gearshape")` are constructed with no action closure
  (`MediaListView.swift:22`, `:26`), so they render as tappable controls that do nothing. Search
  does not exist; settings is issue #58. Shipping visibly interactive controls that no-op is a
  plausible App Review objection and should be resolved before submission — either wire them up or
  remove them.
- Rows are keyed by `\.url`. Two imports resolving to the same URL collapse to one row;
  `importAudio` already de-duplicates on `url`.
- `deleteAudio` mutates `audioList` directly rather than reloading, so the list and Core Data can
  drift if the delete use case fails — it has no error path.
- The empty state is *not* the same as the CarPlay empty state, which does not exist at all (#95).
- Row order is whatever `LoadAllAudiosUseCase` returns; there is no explicit sort.
