# Media row

`MediaView` — the per-book row rendered inside the library list. A component, not a screen, but it
owns its own view model and player subscription.

## Sub-features

- **artwork:** `DataImageView(data:)` at 64pt, rounded. Falls back to its own placeholder when
  `imageData` is nil.
- **title:** `PlayerTitleView` with `SlidingTextView` underneath — the title scrolls horizontally
  while `isPlaying` is true. This is the subject of issue #54.
- **chapter-count:** `ChapterCountView` bound to `model.currentChapter` over
  `info.chapters.count`, formatted `%d/%d` (`Localizable.chapterCount`).
- **timestamp:** `TimestampView` showing `currentTime` over `info.duration`, formatted `%@/%@`.
- **play-button:** `PlayButtonView` toggling `model.play()` / `model.pause()` for this book
  specifically.
- **download-ring:** for a LibriVox book whose download is incomplete, a `DownloadRingView` sits
  before the play button (`library.row.<n>.downloadRing`). Tapping it pauses a running download or
  resumes a paused one (a paused ring shows a play glyph); its accessibility label is *"Downloading,
  N%"* or *"Paused"*. It disappears when the book is complete and never exists for imported books.
  See [downloads](downloads.md).
- **per-row subscription:** each `MediaViewModel` subscribes to the player's URL publisher. When a
  *different* book starts, the row cancels its time subscription and sets `isPlaying = false`; when
  *its own* book starts, it installs the time subscription.
- **created-while-loaded:** a row built **after** its book was already loaded (the list is rebuilt
  when search closes, or playback began from Siri, CarPlay or another screen) never sees the play
  event, so at init it checks `player.url == info.url` and, if so, takes `isPlaying` from the player
  and installs the time subscription. Without this such a row showed paused and frozen (fix in
  `40643e6`; unit-tested in `MediaViewModelTests`, not by a UI test).

## How to get to it (user POV)

Every row in the library list, and the *In your library* rows in search results (namespace
`library.search.local.<n>` instead of `library.row.<n>`). The play button acts without leaving the
list; tapping anywhere else opens the full player.

## Driving it with abbay-ctl

```bash
$B snapshot                                  # library.row.<n>.{title,chapterCount,timestamp,play}
$B tap library.row.0.play
$B wait library.row.0.play --state pause     # planned: assert the toggled state
$B snapshot | jq '.elements[] | select(.id=="library.row.0.timestamp")'
$B tap library.row.1.play                    # row 0 must stop reporting isPlaying
```

**Verified** (`AccessibilityIdentifierTests`): `library.row.<n>.artwork`,
`library.row.<n>.title`, `library.row.<n>.chapterCount`, `library.row.<n>.timestamp`,
`library.row.<n>.play`. The same leaves exist under `library.search.local.<n>`; of those only
`.title` is verified.

**Implemented but unverified:** `library.row.<n>.downloadRing` — the stub download manager reports no
state, so no UI test can make a ring appear.

`library.row.<n>.title` doubles as the row handle: the tap gesture sits on the whole row, so
tapping the title opens the player. There is deliberately no identifier on the row container —
it would overwrite all five leaves above.

Remember row order is not insertion order (`LoadAllAudiosUseCase` applies no sort), so resolve
`<n>` by matching the title's label rather than assuming a position.

## Gotchas

- **Chapter numbering is 0-based in the model and 1-based only on screen.** `MediaViewModel` stores
  `currentChapter` 0-indexed at init and on every time update; `ChapterCountView` adds one when it
  draws (#104). A paused and a playing row therefore agree: a three-chapter book at rest reads `1/3`,
  a book with no chapters `0/0` (both asserted by UI tests).
- **The ring is a `Button` inside a row whose tap gesture opens the player.** That a tap on the ring
  pauses without also opening the player follows from SwiftUI button precedence and is not covered
  by any test.
- Each row creates its own `PlayerObserver` over the shared player singleton, so a library of N
  books holds N subscriptions. `subscribeToTimePublisher` is guarded to one per observer;
  `subscribeToPlayUrlPublisher` is not (#94).
- `isPlaying` is derived from `player.isPlaying(info.url)`, so it is URL-scoped — two rows can never
  both show playing.
- The sliding title animates only while playing, which makes screenshot comparison of this row
  non-deterministic. Capture state from `snapshot`, not pixels.
