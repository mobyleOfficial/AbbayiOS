# Player (the details screen)

`PlayerView` is the full-screen details screen: cover art, transport controls, scrubbing and the
chapter list. It is **no longer a sheet**. It is drawn inside `PlayerExpansionOverlay`, one panel
above the tabs that grows out of the [mini player](mini-player.md) and collapses back into it. The
panel adds a header on top with a grabber (`player.grabber`, hidden from accessibility) and a close
chevron (`player.close`).
There is one presentation for the whole app (`PlayerPresentation`). Library rows, the bar and a
LibriVox page's Play all open it.

## Sub-features

- **header:** the grabber, a collapse handle that replaces the old sheet grabber, and a
  `chevron.down` close button (`player.close`, label *Close player*). Tapping the chevron collapses
  the screen into the bar, animated. Dragging the grabber, the chevron or the cover down collapses
  it under the finger. The grabber is hidden from VoiceOver (a drag handle only), so the chevron
  is the one *Close player* element; the panel also answers the escape gesture (two-finger Z). Collapse rules are in [mini-player](mini-player.md#sub-features).
- **cover:** artwork at 288 pt with rounded corners. While the panel grows, the overlay draws a
  growing copy of the cover that lands exactly here, and the real cover is hidden until then.
  Below it is the title as a `PlayerTitleView` (`player.title`, sliding while playing).
- **transport:** three controls in a row: back, play/pause, forward. The skips jump by the
  [Settings](settings.md) amounts (10/15/30/45 s, default 15), seek relative to the current
  position, and draw the number in their SF Symbol (`gobackward.N` / `goforward.N`). VoiceOver
  reads *Skip back N seconds* / *Skip forward N seconds*, and play/pause *Play* / *Pause*
  (`PlayButtonView`, since #144). (Before Settings there were five fixed
  controls, ±15 and ±30.)
- **speed:** under the timeline, a capsule button (`player.speed`, label *Playback speed*, value
  e.g. *1.5×*, green when not 1.0×) opens the speed sheet (`SpeedSheetView`, ported from the
  Android app): − / the speed / + in 0.05 steps (`speed.decrease`, `speed.value`, `speed.increase`),
  a 0.5–3.5× slider (`speed.slider`), preset chips 0.8, 1.0, 1.2, 1.5, 1.75, 2.0, 2.5
  (`speed.preset.<n>`), and *Set as default for new books* (`speed.setDefault`, disabled and
  relabelled when the speed already is the default). The speed is **per book**: on the loaded book
  it applies at once (`Player.setPlaybackRate`); on another book it is remembered for when it plays.
  The player applies it through the one `AVQueuePlayer`'s `defaultRate`, so it holds across pause
  and resume, seeks and chapter-file advances, and publishes it to Now Playing.
- **loaded vs other book:**
  - **The loaded book** (the one in the player) shows the player's state: `isPlaying` from
    `PlaybackState`, time and chapter from `PlaybackClock`.
  - **Another book** (a row tap on a book that isn't loaded) shows its saved position. Its
    transport does nothing until Play (or a chapter tap, see *chapter-list-gating*) loads it, so
    it can't move the loaded book.
  - **Following the loaded book:** opened on the loaded book, the screen follows it. If Siri or
    CarPlay switches books while it is open, it shows the new one. Each presentation gets a fresh
    `PlayerViewModel` (`PlayerDetailsModels`), so reopening book A never shows the previously
    followed book B.
- **scrubbing:** `PlayerProgressView` over book time. While the finger scrubs, and until the clock
  reports the seek, the slider shows the scrubbed time, so it doesn't jump back for a tick.
- **chapter-list:** the shared `ChapterListView` (also used by the
  [LibriVox details page](librivox-details.md)): a rounded card with a *"Chapter selection"* header
  (`player.chapters.title`), then one row per chapter (`player.chapter.<n>`) with a scrolling title
  and its duration. The current chapter renders in the "playing" style (green). Tapping a chapter
  plays it from its `startTime`. On iOS 18+, a downward drag from the list's top collapses the screen.
- **no-chapters:** a book with no chapter markers (a plain MP3) shows, under the header, a
  `list.bullet` glyph, *No chapters* and *This book has no chapter markers, so it plays from start
  to finish.* (`player.chapters.empty`, one combined element), filling the space the list would
  have. It is styled like the library's empty state, not `ContentUnavailableView`.
- **chapter-list-gating:** none any more (owner decision, #166). **Tapping a chapter always plays
  that chapter of the book the screen shows**, playing or paused, and the rows are never dimmed
  (they were dimmed to 50% while not playing, and the tap did nothing then).
  `PlayerViewModel.selectChapter`:
  - the shown book is loaded: `Player.playChapter(at:)` seeks to the chapter's start and plays;
  - another book (or none) is loaded: the shown book is loaded first with `Player.play`, at the
    chapter's start rather than its saved position, then `playChapter(at:)`. The screen then
    follows it as the loaded book;
  - the shown book doesn't load (no file, offline and not downloaded, no audio session):
    `Player.play` reports why, as Play does, and nothing seeks the loaded book on its behalf.
    (Before the gate, a tap seeked the *loaded* book: the wrong chapter of the wrong book.)
- **download-status:** for a LibriVox book whose download is **incomplete**, each row also shows ✓,
  `N%`, *Waiting* or *Failed · Retry*, and a thin overall progress bar (`player.download.progress`)
  sits under the header, with why under it while a *Wait for Wi-Fi* book is held by the network:
  cellular (`player.download.cellularHold`), a Personal Hotspot (`player.download.hotspotHold`) or
  Low Data Mode (`player.download.lowDataMode`), see [downloads](downloads.md) *hold-hint*. The
  failed status is a button (`player.chapter.<n>.retry`) that restarts the chapter's download, playing or not; the rest of the row keeps its seek tap. Both vanish when the download completes. Imported books never show them. See
  [downloads](downloads.md).
- **multi-file-books:** a LibriVox book is one book made of many files. Time, the scrubber, the
  skips and chapter seeks all use **book time** (chapter `startTime`s are cumulative).
  `MultiFileQueue` maps book time to a chapter file and an offset. It keeps the next file queued for
  gapless playback, prefers the downloaded file over streaming, and pauses at the end of the last
  chapter. Seeking into a different chapter loads that file and prioritizes its download.
- **chapter-skips:** `Player.skipToNextChapter` / `skipToPreviousChapter`, shared by the
  [mini player](mini-player.md)'s swipe, the lock screen and CarPlay ([now-playing](now-playing.md))
  and the Siri intents. While a seek is in flight, `Player.currentTime` is that seek's target
  (single file: `Player`'s pending seek; multi-file: `MultiFileQueue.pendingBookTime`), so two
  quick presses go two chapters (#151). Before, a playing `AVPlayer` reported the old time until
  the first seek landed, and both presses aimed at the same chapter.
- **failures:** Play with no URL, an audio session that won't activate, a moved or unreadable file,
  or a LibriVox chapter that fails (offline and not downloaded, or otherwise) each report a notice
  (see [notices](notices.md)). A failed item also pauses the player, so the transport, the bar and
  the row show *Play* again, and one tap on Play retries with a fresh item. (Before, the player
  kept its rate and kept reporting "playing", so the first tap only paused.)
- **what ticks:** the screen's body reads only the slow state. `PlayerTimeline` reads
  `PlaybackClock.bookTime`, so it re-renders once per tick. `PlayerChapters` reads `currentChapter`,
  so it re-renders once per chapter. The screen is built once per book and handed down unchanged,
  so a drag frame doesn't re-run its body.

## How to get to it (user POV)

- Tap a Library row's title or artwork.
- Tap or drag up the mini player.
- Tap **Play** on a LibriVox details page.

To dismiss, tap the chevron, or drag the header, the cover or (iOS 18+) the chapter list from its
top down into the bar.

## Driving it with abbay-ctl

```bash
$B launch -seedLibrary
$B tap library.row.0.title && $B wait player.close       # grows up from the bottom (nothing loaded)
$B tap player.transport.play                              # a seeded book loads and plays (the Debug fixture's audio)
$B tap player.transport.forward && $B snapshot
$B tap player.speed && $B tap speed.preset.1.5 && $B swipe down   # player.speed value "1.5×"
$B tap player.chapter.2                                   # plays chapter 3 of the shown book, paused or not (loads it if needed)
$B tap player.close && $B wait library.list
$B drag player.close down                                 # planned: collapse under the finger (the grabber is not addressable)
```

**Verified** (`AccessibilityIdentifierTests`, `MiniPlayerUITests`):
- `player.title`
- `player.transport.{back,play,forward}` and `player.speed`
- the speed sheet's `speed.{value,increase,decrease,setDefault}` and `speed.preset.<n>`
  (`SettingsUITests.test_speedSheet_*`), and the forward button's label following Settings
  (`test_changingSkipForward_updatesThePlayersButton`)
- `player.chapters.title` and `player.chapter.<n>`
- a chapter tap on a book that isn't loaded, with nothing playing, loads that book: the bar
  appears at the tapped chapter (`MiniPlayerUITests.test_tappingAChapter_ofABookNotLoaded_loadsIt`,
  seeded long book: the bar reads *Chapter 4*), and it plays from the tapped chapter, not the saved position
  (`test_chapterTap_bookNotLoaded_playsThatChapter`, `-seedPlayableBook`: the transport flips to
  *Pause* and the bar reads *Chapter 4*). The three cases are unit-tested in
  `PlayerViewModelChapterTapTests`.
- `player.chapters.empty` on "Seeded Plain Book", and its absence on "Seeded Chaptered Book"
  (`EmptyStateUITests`)
- `player.close` (`test_player_closeButton_dismisses`)
- `player.grabber` is set but **hidden from accessibility**, so XCUITest can't resolve it: the UI
  tests drag from its position, found from `player.close` (`grabberCenter()` in
  `MiniPlayerUITests`, `test_draggingDetailsDown_collapses`; a downward swipe from the chevron also
  dismisses, `test_player_swipeDown_dismisses`)

The screen is reached by a row tap, the bar (tap and drag) and Play on the stub LibriVox book's
details page.

`player.download.progress`, `player.download.lowDataMode`, `player.download.hotspotHold` and
`player.chapter.2.retry` are verified by `DownloadStatusUITests` (`-stubDownloadStates` with a
`-stubPath*` argument, the stub book opened from the Library). **Implemented but unverified:**
`player.download.cellularHold` (same view and mapping; `ChapterListViewTests`).

Speed itself (the requested `rate`/`defaultRate` across pause, seek and files) is unit-tested in
`PlayerSpeedTests`; the seeded books play real audio since #147, but no UI test measures the rate.

**Not addressable:** there is no `player.root`. It overwrote the title, all the transport controls
and the chapter list. Wait on `player.close` or `player.transport.play` to know the screen is up.
It slides in, so let it arrive before tapping inside it (the UI tests wait for `player.close` to
reach the top quarter of the screen).

**Not implemented:** `player.cover`, and `player.progress` with its `.current` / `.total` labels.
The progress view is a composite (a `ProgressView`, a drag handle and two `Text`s), so it needs
identifiers threaded through the component, not applied from the call site.

## Gotchas

- **A chapter tap starts playback, even from pause, and can switch books.** Since #166's owner
  decision there is no `isPlaying` gate and no dimming: tapping a row of a book that isn't loaded
  loads it (the previous book stops) at that chapter. A UI test that taps a chapter therefore
  changes the loaded book; open the book you mean first. Every seed but *Seeded Missing Book*
  plays from the chapter (#147); on *Seeded Long Book* a chapter past the 13th starts past the end
  of the 14-minute audio. It makes sound: pause it afterwards.
- **The overlay stays hit-testable only while a book is presented** (`allowsHitTesting`). After a
  close, taps reach the tabs once the collapse finishes.
- `PlayerProgressView.swift:44` still uses the deprecated `onChange(of:perform:)` (deprecated as of
  iOS 17, the app's deployment target).
- The chapter list is keyed by `\.offset` from `enumerated()`, so identifiers are positional. A book
  with duplicate chapter titles is still addressable by index.
- **Multi-file playback is covered by unit tests only** (`PlayerMultiFileTests` and
  `BookTimelineTests`):
  - the saved-position chapter load
  - local files over remote ones
  - cross-file seeks
  - book-time saves
  - no bookmark for `librivox://` URLs

  No UI test or committed audio fixture plays a multi-file book, and the stub LibriVox chapter
  points at `/dev/null`. Gapless hand-off and streaming an undownloaded chapter are unproven on a
  device or simulator.
- Seeking past the final chapter boundary isn't specially handled. `currentChapter(for:)` clamps by
  scanning chapter ranges.
