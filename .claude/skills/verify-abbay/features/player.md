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
- **chapter-list:** the shared `ChapterListView` (also used by the
  [LibriVox details page](librivox-details.md)): a rounded card with a *"Chapter selection"* header
  bar, then a scrolling `List` with one row per chapter — scrolling title, trailing duration. The
  chapter matching `model.currentChapter` renders in the "playing" style (green). Tapping a chapter
  seeks to its `startTime`.
- **chapter-list-gating:** the whole list is dimmed to 50% opacity when not playing, and the tap
  handler early-returns unless `model.isPlaying`.
- **download-status:** for a LibriVox book whose download is **incomplete**, each row also shows ✓ /
  `N%` / *Waiting* and a thin overall progress bar (`player.download.progress`) sits under the header.
  Both vanish when the download completes; imported books never show them. See
  [downloads](downloads.md).
- **multi-file-books:** a LibriVox book is one book of many files. Time, the scrubber, the skip
  buttons and chapter seeks all use **book time** (chapter `startTime`s are cumulative);
  `MultiFileQueue` maps it to a chapter file and offset, keeps the next file queued for gapless
  playback, prefers the downloaded file over streaming, and pauses at the end of the last chapter.
  Seeking into a different chapter loads that file and prioritizes its download.

## How to get to it (user POV)

Library → tap any row (or an *In your library* search result), tap the floating player, or tap
**Play** on a LibriVox details page. Dismissed by the sheet's drag indicator or a
downward swipe — there is no explicit close button.

## Driving it with abbay-ctl

```bash
$B tap library.row.0 && $B wait player.transport.play
$B tap player.transport.play
$B tap player.transport.forward15 && $B snapshot    # assert player.progress.current advanced
$B scrub player.progress 0.5                        # planned: drag to a fraction of duration
$B tap player.chapter.2 && $B wait player.chapter.2 --state current
$B screenshot player-chapter-2
$B swipe down                                       # dismiss: drag from the sheet's top edge, not a control
```

**Verified** (`AccessibilityIdentifierTests`): `player.title`,
`player.transport.{back30,back15,play,forward15,forward30}`, `player.chapters.title`,
`player.chapter.<n>`. Reached by tapping a Library row, and by Play on the stub LibriVox book's
details page (`test_search_showsFloatingPlayerAfterPlayingFromDetail`).

**Implemented but unverified:** `player.download.progress` — only rendered while a download is
incomplete, which the stub download manager never reports.

**Not addressable:** there is no `player.root` — it overwrote the title, all five transport controls and the
chapter list. Wait on `player.transport.play` instead to know the sheet is up.

**Not implemented:** `player.cover`, and `player.progress` with its `.current` / `.total`
labels. The progress view is a composite (a `ProgressView`, a drag handle and two `Text`s) and
needs identifiers threaded through the component, not applied from the call site.

## Gotchas

- **You cannot tap a chapter while paused.** `chaptersView`'s tap handler is
  `guard model.isPlaying, …` in the `onSelect` closure passed to `ChapterListView`. The list is
  visibly dimmed but still looks tappable, so this reads as a broken control rather than a deliberate gate. Any
  chapter-seek proof must start playback first.
- `onChange(of:perform:)` is used here (`PlayerView.swift:108`) and is deprecated as of iOS 17,
  which is the app's own deployment target. Same in `FloatingPlayerView.swift:53` and
  `PlayerProgressView.swift:44`. This is the most likely cause of issue #54's animation glitch, and
  it is one of the things Xcode 27 is strictest about.
- The chapter list is keyed by `\.offset` from `enumerated()`, so identifiers are positional. A book
  with duplicate chapter titles is still addressable by index.
- The sheet is presented from `MediaListView` on `tappedAudio`, which is set by both the row tap and
  the floating-player tap — same screen, two entry points, and the map's coverage set includes both.
- **Multi-file playback is covered by unit tests only** (`PlayerMultiFileTests`, `BookTimelineTests`:
  saved-position chapter load, local-over-remote, cross-file seeks, book-time saves, no bookmark for
  `librivox://` URLs). No UI test or committed audio fixture plays a multi-file book; the stub
  LibriVox chapter points at `/dev/null`. Gapless hand-off and streaming of an undownloaded chapter
  are unproven on a device/simulator.
- There is no close button. A driver that cannot swipe must relaunch to escape the sheet.
- Seeking past the final chapter boundary is not specially handled; `currentChapter(for:)` clamps by
  scanning chapter ranges.
