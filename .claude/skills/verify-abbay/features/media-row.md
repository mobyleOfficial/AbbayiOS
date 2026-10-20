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
- **per-row subscription:** each `MediaViewModel` subscribes to the player's URL publisher. When a
  *different* book starts, the row cancels its time subscription and sets `isPlaying = false`; when
  *its own* book starts, it installs the time subscription.

## How to get to it (user POV)

Every row in the library list. The play button acts without leaving the list; tapping anywhere
else opens the full player.

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
`library.row.<n>.play`.

`library.row.<n>.title` doubles as the row handle: the tap gesture sits on the whole row, so
tapping the title opens the player. There is deliberately no identifier on the row container —
it would overwrite all five leaves above.

Remember row order is not insertion order (`LoadAllAudiosUseCase` applies no sort), so resolve
`<n>` by matching the title's label rather than assuming a position.

## Gotchas

- **Chapter numbering is inconsistent between init and updates.** At construction
  `currentChapter = info.currentChapter(for: currentTime)` (0-indexed), but the time subscription
  sets `info.currentChapter(for:) + 1` (1-indexed) (`MediaViewModel.swift:32` vs `:62`). A paused
  row and a playing row therefore disagree by one. Assert on the *playing* value.
- Each row creates its own `PlayerObserver` over the shared player singleton, so a library of N
  books holds N subscriptions. `subscribeToTimePublisher` is guarded to one per observer;
  `subscribeToPlayUrlPublisher` is not (#94).
- `isPlaying` is derived from `player.isPlaying(info.url)`, so it is URL-scoped — two rows can never
  both show playing.
- The sliding title animates only while playing, which makes screenshot comparison of this row
  non-deterministic. Capture state from `snapshot`, not pixels.
