# Player

`PlayerView` — the full-screen player, presented as a sheet. Cover art, transport controls,
scrubbing, and the chapter list.

## Sub-features

- **cover:** artwork at 288pt rounded, with the title below as a `PlayerTitleView` (sliding while
  playing), centre-aligned.
- **transport:** five controls in a row — `gobackward.30`, `gobackward.15`, play/pause,
  `goforward.15`, `goforward.30`. The skips call `Player.backward/forward(withSeconds:)`, which
  seek relative to the current position.
- **scrubbing:** `PlayerProgressView` bound to `currentTime` over `info.duration`. Drag start calls
  `willSeek()`, release calls `seek(time)`. Current time drives `setCurrentChapter(for:)` through an
  `onChange`.
- **chapter-list:** a titled section (*"Chapter selection"*) listing every chapter. The chapter
  matching `model.currentChapter` renders in the "playing" style. Tapping a chapter seeks to its
  `startTime`.
- **chapter-list-gating:** the whole list is dimmed to 50% opacity when not playing, and the tap
  handler early-returns unless `model.isPlaying`.

## How to get to it (user POV)

Library → tap any row, or tap the floating player. Dismissed by the sheet's drag indicator or a
downward swipe — there is no explicit close button.

## Driving it with abbay-ctl

```bash
$B tap library.row.0 && $B wait player.root
$B tap player.transport.play
$B tap player.transport.forward15 && $B snapshot    # assert player.progress.current advanced
$B scrub player.progress 0.5                        # planned: drag to a fraction of duration
$B tap player.chapter.2 && $B wait player.chapter.2 --state current
$B screenshot player-chapter-2
$B swipe player.root down                           # dismiss the sheet
```

Identifiers to add: `player.root`, `player.cover`, `player.title`,
`player.transport.{back30,back15,play,forward15,forward30}`,
`player.progress` (+ `.current`, `.total`), `player.chapters.title`, `player.chapter.<n>`.

## Gotchas

- **You cannot tap a chapter while paused.** `chaptersView`'s tap handler is
  `guard model.isPlaying else { return }` (`PlayerView.swift:139`). The list is visibly dimmed but
  still looks tappable, so this reads as a broken control rather than a deliberate gate. Any
  chapter-seek proof must start playback first.
- `onChange(of:perform:)` is used here (`PlayerView.swift:102`) and is deprecated as of iOS 17,
  which is the app's own deployment target. Same in `FloatingPlayerView.swift:53` and
  `PlayerProgressView.swift:43`. This is the most likely cause of issue #54's animation glitch, and
  it is one of the things Xcode 27 is strictest about.
- The chapter list is keyed by `\.offset` from `enumerated()`, so identifiers are positional. A book
  with duplicate chapter titles is still addressable by index.
- The sheet is presented from `MediaListView` on `tappedAudio`, which is set by both the row tap and
  the floating-player tap — same screen, two entry points, and the map's coverage set includes both.
- There is no close button. A driver that cannot swipe must relaunch to escape the sheet.
- Seeking past the final chapter boundary is not specially handled; `currentChapter(for:)` clamps by
  scanning chapter ranges.
