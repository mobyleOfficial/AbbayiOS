# Media row (the library cell)

`MediaView` — one book's cell in the library's cover grid (#166 G3; it was a list row until
then, and keeps the `library.row.<n>` namespace). A component, not a screen. It holds **no player
subscriptions**: it reads the app-wide `PlaybackState` and its own book's `BookDownloadEntry` from
the SwiftUI environment (injected by `playbackEnvironment(_:)` at the app root), and sends actions
through `MediaViewModel` straight to `PlaybackCenter.player`.

## Sub-features

- **artwork:** `ArtworkView(book:cornerRadius: 10, shadow: true)`, square, as wide as the column. A
  book without artwork shows the generic tile (dark gradient, `headphones` for an import,
  `book.closed` for a LibriVox book), never the `photo` symbol (#166 G6). One image element, so
  `library.row.<n>.artwork` stays a leaf. `-seedArtwork` gives three seeds generated covers.
- **title:** plain `Text`, `.footnote` semibold, on a fixed two-line height
  (`lineLimit(2, reservesSpace: true)`) so every cell in a grid row is as tall as the others. It
  turns malachite while the cell's book is playing (VoiceOver value *Now playing*). The sliding
  title (`PlayerTitleView`) is no longer used here.
- **detail (status line):** one line, `.caption`: *Finished ✓* once listened to within 30 s of the
  end (`DownloadHousekeeping.isFinished`, the same rule as Settings' *Delete finished downloads*),
  *New* at 0 s, else *Ch N/M* for a chaptered book (`Localizable.rowChapter`, 1-based) or the time
  left (`Localizable.rowTimeLeft`, e.g. "3m 20s left", plural rules in pt-BR, #152). No author any
  more. An idle cell computes it from the saved `currentTime`; the loaded book's cell shows
  `RowProgressView` instead, with live values from `PlaybackClock` (a chaptered book there always
  reads *Ch N/M*).
- **progress:** a 3 pt malachite capsule under the status line while the book is started and not
  finished. Its slot keeps its height when hidden. Live for the loaded book.
- **download-ring:** for a LibriVox book whose download is incomplete, a `DownloadRingView` on a
  dark disc over the cover's bottom-trailing corner (`library.row.<n>.downloadRing`). Tapping it
  pauses a running download or resumes a paused one (a paused ring shows a play glyph); its
  accessibility label is *"Downloading, N%"* or *"Paused"*. A *Wait for Wi-Fi* book the network
  holds shows the hold's glyph inside the ring and adds why: *"Downloading, 33%. Waiting for
  Wi-Fi: on cellular"* (#171; reasons in [downloads](downloads.md) *hold-hint*). It disappears when
  the book is complete and never exists for imported books.
- **downloaded-badge:** while the library search has text, a fully downloaded LibriVox book has a
  *Downloaded* / *Baixado* capsule on the cover's bottom-leading corner (a badge, so the cell keeps
  its height).
- **tap:** anywhere on the cell except the ring opens the player (`presentation.open`), as the row
  did. There is no play button on the cell.
- **context-menu:** a long press opens a menu with **Play** / **Pause** (`library.row.<n>.play`)
  and **Delete** (`library.row.<n>.delete`, destructive; `MediaListViewModel.deleteAudio`, the old
  swipe's semantics). The same two are VoiceOver custom actions on the title.
- **created-while-loaded:** a cell built after its book was already loaded shows it playing with no
  play event to catch, because it compares its URL with `PlaybackState.loadedBook` (#116;
  unit-tested in `MediaViewModelTests`).

## Hard rule: idle cells do zero work per tick

The body reads only `MediaView.DetailModel`, which reads `PlaybackState.loadedBook` and — only
when this cell's book is the loaded one — `PlaybackState.isPlaying`, plus the book's own download
entry. Nothing in it reads `PlaybackClock`. `RowProgressView`, the one cell view that reads the
clock, is inserted only for the loaded book; its status line for a chaptered book reads only
`currentChapter`, and its progress bar reads `bookTime`. Pinned by `MediaViewModelTests`
(`test_idleRow_readsNoClockProperty`, `test_rowModel_makesNoPlayerSubscriptions`) and, app-wide, by
`SubscriptionBudgetTests`.

**Once per book switch, every cell re-renders**, as rows did: each `DetailModel` reads
`PlaybackState.loadedBook`. Constant per switch, independent of the clock.

## How to get to it (user POV)

Every cell in the Library tab's grid, including while its local search filters it (cells keep the
`library.row.<n>` namespace, positional within the filtered grid, left to right then down).

## Driving it with abbay-ctl

```bash
$B snapshot                                  # library.row.<n>.{artwork,title,detail}
$B press library.row.0.title                 # long press: the context menu
$B tap library.row.0.play                    # Play / Pause from the menu
$B press library.row.1.title && $B tap library.row.1.delete
```

**Verified:** `AccessibilityIdentifierTests` (`library.row.<n>.{artwork,title,detail}`, and with
the menu open `.play` and `.delete`); `LibraryGridUITests` (status line "Ch 2/3" under
`-seedLastPlayed`, *New* and *Finished ✓* under `-seedTimeLeftEdges`, delete from the menu down to
`library.empty`). `MiniPlayerUITests` and `NoticeUITests` play seeded books through the menu
(`AbbayUITests/LibraryGridActions.swift`).

`library.row.<n>.downloadRing` is verified by `DownloadStatusUITests`
(`test_libraryRing_saysWhyTheDownloadWaits_andPausedOnceTapped`).

`library.row.<n>.title` doubles as the cell handle: tap it to open the player, long-press it for
the menu. There is deliberately no identifier on the cell container — it would overwrite the
leaves.

Cell order is not insertion order (`LoadAllAudiosUseCase` applies no sort), so resolve `<n>` by
matching the title's label rather than assuming a position.

## Gotchas

- **The menu items exist only while the menu is open.** Long-press first (XCUITest:
  `press(forDuration: 1.2)`); a tap off the menu closes it.
- **Chapter numbering is 0-based in the model and 1-based only on screen**
  (`ChapterCountView.displayNumber`, #104). A chaptered book at rest now reads *New*, not
  `Ch 1/3`; started, it reads its chapter.
- **An idle cell's status uses the saved position.** `audioList` loads once, so on every book
  switch `MediaListViewModel` re-reads the outgoing and incoming books from storage.
- **The ring is a `Button` inside a cell whose tap gesture opens the player.** That a tap on the
  ring pauses without also opening the player follows from SwiftUI button precedence and is not
  covered by any test.
