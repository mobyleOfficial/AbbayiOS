# Media row

`MediaView` — the per-book row rendered inside the library list. A component, not a screen. It
holds **no player subscriptions**: it reads the app-wide `PlaybackState` and its own book's
`BookDownloadEntry` from the SwiftUI environment (injected by `playbackEnvironment(_:)` at the app
root), and sends actions through `MediaViewModel` straight to `PlaybackCenter.player`.

## Sub-features

- **artwork:** `ArtworkView(book:)` at 64 pt: rounded by size (8 pt), a 0.5 pt inner stroke. A
  book without artwork shows the generic tile (dark gradient, `headphones` for an import,
  `book.closed` for a LibriVox book), never the `photo` symbol (#166 G6). One image element, so
  `library.row.<n>.artwork` stays a leaf.
- **title:** `PlayerTitleView` with `SlidingTextView` underneath — the title scrolls horizontally
  and turns malachite while the row's book is playing. This is the subject of issue #54.
- **detail:** one line, `author · Ch N/M` for a chaptered book (`Localizable.rowChapter`, 1-based),
  else `author · <time left>` (`Localizable.rowTimeLeft`, e.g. "3m 20s left"; a finished book
  "0s left" / "0s restantes", plural in pt-BR through the string's `zero` form, #152;
  `-seedTimeLeftEdges` seeds *Seeded Finished Book* to show it). The author and its
  separator are dropped when the book has none. An idle row computes it from the saved
  `currentTime`; the loaded book's row shows `RowProgressView` instead, with live values from
  `PlaybackClock`.
- **play-button:** `PlayButtonView` calling `play()` / `pause()` for this book. Its glyph follows
  `PlaybackState.isPlaying`, so a pause from Control Center or Siri shows immediately.
- **download-ring:** for a LibriVox book whose download is incomplete, a `DownloadRingView` sits
  before the play button (`library.row.<n>.downloadRing`). Tapping it pauses a running download or
  resumes a paused one (a paused ring shows a play glyph); its accessibility label is *"Downloading,
  N%"* or *"Paused"*. A *Wait for Wi-Fi* book the network holds shows the hold's glyph inside the
  ring (light grey) and adds why: *"Downloading, 33%. Waiting for Wi-Fi: on cellular"* (#171; the
  reasons are in [downloads](downloads.md) *hold-hint*). It disappears when the book is complete and
  never exists for imported books.
- **created-while-loaded:** a row built after its book was already loaded (the list is filtered or
  scrolled back into view, or playback began from Siri, CarPlay or another tab) shows it playing with no
  play event to catch, because it compares its URL with `PlaybackState.loadedBook` (#116;
  unit-tested in `MediaViewModelTests`).

## Hard rule: idle rows do zero work per tick

The body reads only `MediaView.DetailModel`, which reads `PlaybackState.loadedBook` and — only
when this row's book is the loaded one — `PlaybackState.isPlaying`, plus the book's own download
entry. Nothing in it reads `PlaybackClock`. `RowProgressView`, the one row view that reads the
clock, is inserted only for the loaded book; for a chaptered book it reads only `currentChapter`,
so ticks within a chapter cost it nothing. Pinned by `MediaViewModelTests`
(`test_idleRow_readsNoClockProperty`, `test_rowModel_makesNoPlayerSubscriptions`) and, app-wide, by
`SubscriptionBudgetTests` (25 rows, three open/close cycles, 30 ticks: still three player
subscriptions and one `statesPublisher` subscription in total).

**Once per book switch, every row re-renders.** Each row's `DetailModel` reads
`PlaybackState.loadedBook` to tell whether it is the loaded one, so a switch (not a tick, not a
pause) invalidates every visible row once. That is the accepted cost of rows holding no
subscriptions; it is constant per switch and independent of the clock.

## How to get to it (user POV)

Every row in the Library tab's list, including while its local search filters it (rows keep the
`library.row.<n>` namespace, positional within the filtered list). The play button (VoiceOver:
*Play* / *Pause*, since #144) acts without leaving the list; tapping anywhere else opens the details
screen ([player](player.md)).

## Driving it with abbay-ctl

```bash
$B snapshot                                  # library.row.<n>.{artwork,title,detail,play}
$B tap library.row.0.play
$B snapshot | jq '.elements[] | select(.id=="library.row.0.detail")'
$B tap library.row.1.play                    # row 0 must stop reporting playing
```

**Verified** (`AccessibilityIdentifierTests`): `library.row.<n>.artwork`,
`library.row.<n>.title`, `library.row.<n>.detail` (`AccessibilityID.Element.detail`; its label:
"Ch 1/3" for the chaptered seed, the time left for the plain one), `library.row.<n>.play`
(also used by `MiniPlayerUITests` to load a seeded book).

`library.row.<n>.downloadRing` is verified by `DownloadStatusUITests`
(`test_libraryRing_saysWhyTheDownloadWaits_andPausedOnceTapped`): with `-stubDownloadStates
-stubPathCellular` the stub book added with *Wait for Wi-Fi* shows a ring labelled *"Downloading,
33%. Waiting for Wi-Fi: on cellular"*, and *"Paused"* once tapped. Label and glyph rules:
`ChapterListViewTests` (*Download ring*).

`library.row.<n>.title` doubles as the row handle: the tap gesture sits on the whole row, so
tapping the title opens the details screen. There is deliberately no identifier on the row container —
it would overwrite all the leaves above.

Remember row order is not insertion order (`LoadAllAudiosUseCase` applies no sort), so resolve
`<n>` by matching the title's label rather than assuming a position.

## Gotchas

- **Chapter numbering is 0-based in the model and 1-based only on screen.** The conversion is
  `ChapterCountView.displayNumber` (#104): a three-chapter book at rest reads `Ch 1/3`.
- **An idle row's detail uses the saved position.** `audioList` loads once, so on every book
  switch `MediaListViewModel` re-reads the outgoing and incoming books from storage (the player
  saves the outgoing position before announcing the new book). That keeps the left book's row, and
  a replay of it, at where it stopped, and gives later presses the bookmark the player made.
- **The ring is a `Button` inside a row whose tap gesture opens the player.** That a tap on the ring
  pauses without also opening the player follows from SwiftUI button precedence and is not covered
  by any test.
- The sliding title animates only while playing, which makes screenshot comparison of this row
  non-deterministic. Capture state from `snapshot`, not pixels.
