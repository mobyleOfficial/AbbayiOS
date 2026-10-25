# Player (the details screen)

`PlayerView` is the full-screen details screen, "Player A" of the Liquid Glass redesign (#166 G1):
a large cover, a left-aligned title block, the scrubber, the transport, and two glass pills (speed
and chapters). The chapters open as a glass panel over the cover (G2). It is **no longer a sheet**.
It is drawn inside `PlayerExpansionOverlay`, one panel above the tabs that grows out of the
[mini player](mini-player.md) and collapses back into it. The overlay paints the background (the
book's cover tint fading to near-black) and adds a header on top with a grabber (`player.grabber`,
hidden from accessibility) and a glass close button (`player.close`).
There is one presentation for the whole app (`PlayerPresentation`). Library rows, the bar and a
LibriVox page's Play all open it.

## Sub-features

- **background:** a vertical gradient from the book's cover tint (`CoverTint`, the mini player's
  colour) to near-black: `CoverTintBackground(book:style: .playerGradient)`, black laid over the
  tint at 0% → 45% → 82%. The overlay draws it at full-screen size behind the growing panel, with
  the bar's flat tint over it fading out as the panel grows, so the bar reads as one surface
  changing size. A book without artwork has the `onyx` tint. `-seedCoverArt` gives two seeds a
  cover, so the tint can be seen.
- **header:** a glass circular close button (⌄, `abbayGlass(in: Circle(), interactive: true)`,
  `player.close`, label *Close player*) on the left and the grabber in the middle. No ⋯ button:
  there is nothing to put in it yet. Tapping ⌄ collapses the screen into the bar, animated.
  Dragging the grabber, the button or the cover down collapses it under the finger. The grabber is
  hidden from VoiceOver (a drag handle only), so ⌄ is the one *Close player* element; the panel
  also answers the escape gesture (two-finger Z). Collapse rules are in
  [mini-player](mini-player.md#sub-features).
- **cover:** `ArtworkView(book:cornerRadius: 14, shadow: true)`, as wide as the screen less 24 pt
  margins (up to 360 pt), square, with a soft shadow; no artwork shows the generic tile, as in the
  [media row](media-row.md). On a short screen it shrinks, staying square, so the title, scrubber,
  transport and pills keep their room. While the panel grows, the overlay draws a growing copy of
  the cover (radius 4 → 14, the shadow from half-way) that lands exactly here, and the real cover
  is hidden until then.
- **title:** left-aligned. The title (`player.title`) in `.title3.bold()`, white, up to two lines
  (it no longer turns green while playing or slides). Under it, `PlayerSubtitle`: *author · Ch N
  of M* (pt-BR *Cap. N de M*), the author alone for a book with no chapters, the position alone
  without an author.
- **transport:** three controls in a row, larger than before (32 pt skips, a 44 pt play/pause,
  white in both states): back, play/pause, forward. The skips jump by the
  [Settings](settings.md) amounts (10/15/30/45 s, default 15), seek relative to the current
  position, and draw the number in their SF Symbol (`gobackward.N` / `goforward.N`). VoiceOver
  reads *Skip back N seconds* / *Skip forward N seconds*, and play/pause *Play* / *Pause*
  (`PlayButtonView`, since #144). (Before Settings there were five fixed
  controls, ±15 and ±30.)
- **speed:** the left glass pill (`player.speed`, label *Playback speed*, value e.g. *1.5×*; its
  text is the speed, green when not 1.0×) opens the speed sheet (`SpeedSheetView`, ported from the
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
- **scrubbing:** `PlayerProgressView` over **book** time: a 6 pt capsule track with a white fill
  (a white thumb while dragging), and under it the elapsed time, the **current chapter's name**
  (centre, truncating) and the time remaining with a minus sign, in compact form ("17:12",
  "−1:05:09"). A touch anywhere along the track scrubs. While the finger scrubs, and until the
  clock reports the seek, the slider shows the scrubbed time, so it doesn't jump back for a tick.
- **chapters-pill:** the right glass pill (`player.chapters`, *☰ Chapters* / *Capítulos*) opens the
  chapter panel; while it is open it shows *✕* and its label is *Close chapters*. **A book with no
  chapter markers (a plain MP3) has no pill**, so there is no "No chapters" message on this screen
  any more (`player.chapters.empty` is gone).
- **chapter-panel:** (#166 G2, `ChaptersPanel`) a glass panel (`abbayGlass` in a 26 pt rounded
  rectangle, tinted 35% black) that grows from the pill's corner and floats over the cover, above
  the pills, with a faint dim behind it. Nothing else on the screen moves. It spans the width less
  40 pt on the left and 16 on the right, and is up to 440 pt tall (about eight rows), less on a
  short screen, never less than `PlayerView.minChapterListHeight` (224 pt) on any iPhone (#203).
  - a small handle at its top (`player.chapters.panel`, VoiceOver *Close chapters*, a button)
  - the *Chapters* header (`player.chapters.title`) with the time left in the book ("7h 26m left")
  - one row per chapter (`player.chapter.<n>`), the shared `ChapterListView` rows (#166 G6): the
    number, the title (two lines, never truncated into the trailing column), the duration
    ("42m"); *finished* rows dimmed with a `checkmark.circle`; the *current* row malachite with ▶︎,
    a thin progress bar under its title and "28m left". The panel reads the clock but redraws its
    rows only when what they show changes (`ChaptersPanelContent` is `Equatable`; the progress
    moves in 1% steps).
  - it opens scrolled so the current chapter is in view.
  - **closing:** a tap on a row (it also plays that chapter), a tap outside it (on the dim), the
    pill (✕), the handle, the escape gesture, or a drag down that starts on its top (the handle or
    the header, `ChaptersPanel.closesOnDrag`). A drag on the list scrolls it. Animated with a
    spring; Reduce Motion fades it instead of growing it.
  - the list no longer collapses the player: the chapter list's drag-to-collapse from its top
    (`ExpansionListCollapse`, `ListCollapseModifier`, iOS 18+) was deleted. The header still
    collapses the player exactly as before.
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
- **download-status:** for a LibriVox book whose download is **incomplete**, a thin overall
  progress line (`player.download.progress`) sits under the scrubber's labels on the screen itself,
  always visible, with why under it while a *Wait for Wi-Fi* book is held by the network: cellular
  (`player.download.cellularHold`), a Personal Hotspot (`player.download.hotspotHold`) or Low Data
  Mode (`player.download.lowDataMode`), see [downloads](downloads.md) *hold-hint*. In the chapter
  panel each row shows its status: `N%`, *Waiting*, *Failed · Retry* or ✓ (downloaded). A
  *finished* chapter that is downloaded shows only its finished check, not a second ✓ (#225). The
  failed status is a button (`player.chapter.<n>.retry`) that restarts the chapter's download,
  playing or not; the rest of the row keeps its tap. All of it vanishes when the download
  completes. Imported books never show them. See [downloads](downloads.md).
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
  `PlaybackClock.bookTime`, so it re-renders once per tick. `PlayerSubtitle` reads
  `currentChapter`, so it re-renders once per chapter. The open chapter panel reads the clock, but
  its rows redraw only when their text or 1% progress changes. The screen is built once per book and handed down unchanged,
  so a drag frame doesn't re-run its body.

## How to get to it (user POV)

- Tap a Library row's title or artwork.
- Tap or drag up the mini player.
- Tap **Play** on a LibriVox details page.

To dismiss, tap ⌄, or drag the header or the cover down into the bar. The chapter panel closes
on its own (a tap outside, its ✕ pill, a drag down from its top) and never closes the player.

## Driving it with abbay-ctl

```bash
$B launch -seedLibrary -seedCoverArt                     # two seeds get a warm cover, for the tint
$B tap library.row.0.title && $B wait player.close       # grows up from the bottom (nothing loaded)
$B tap player.transport.play                              # a seeded book loads and plays (the Debug fixture's audio)
$B tap player.transport.forward && $B snapshot
$B tap player.speed && $B tap speed.preset.1.5 && $B swipe down   # player.speed value "1.5×"
$B tap player.chapters && $B wait player.chapters.panel  # the glass chapter panel, at the current chapter
$B tap player.chapter.2                                   # plays chapter 3 of the shown book, paused or not (loads it if needed); closes the panel
$B tap player.close && $B wait library.list
$B drag player.close down                                 # planned: collapse under the finger (the grabber is not addressable)
```

**Verified** (`AccessibilityIdentifierTests`, `MiniPlayerUITests`):
- `player.title`
- `player.transport.{back,play,forward}` and `player.speed`
- the speed sheet's `speed.{value,increase,decrease,setDefault}` and `speed.preset.<n>`
  (`SettingsUITests.test_speedSheet_*`), and the forward button's label following Settings
  (`test_changingSkipForward_updatesThePlayersButton`)
- `player.chapters` (the pill), then `player.chapters.panel`, `player.chapters.title` and
  `player.chapter.<n>` in the panel
- the panel (`ChaptersPanelUITests`): it opens at the current chapter (a tap on chapter 11 of the
  long book, then reopening), a drag down from its handle closes only the panel and the header
  still collapses the player, a tap outside or on the ✕ pill closes it, and the 60-chapter list
  scrolls inside it without moving or collapsing the player
- a chapter tap on a book that isn't loaded, with nothing playing, loads that book: the bar
  appears at the tapped chapter (`MiniPlayerUITests.test_tappingAChapter_ofABookNotLoaded_loadsIt`,
  seeded long book: the bar reads *Chapter 4*), and it plays from the tapped chapter, not the saved position
  (`test_chapterTap_bookNotLoaded_playsThatChapter`, `-seedPlayableBook`: the transport flips to
  *Pause* and the bar reads *Chapter 4*). The three cases are unit-tested in
  `PlayerViewModelChapterTapTests`.
- no `player.chapters` pill on "Seeded Plain Book", and the pill opening the rows on "Seeded
  Chaptered Book" (`EmptyStateUITests`)
- `player.close` (`test_player_closeButton_dismisses`)
- `player.grabber` is set but **hidden from accessibility**, so XCUITest can't resolve it: the UI
  tests drag from its position, found from `player.close` (`grabberCenter()` in
  `MiniPlayerUITests`, `test_draggingDetailsDown_collapses`; a downward swipe from the chevron also
  dismisses, `test_player_swipeDown_dismisses`)

The screen is reached by a row tap, the bar (tap and drag) and Play on the stub LibriVox book's
details page.

`player.download.progress`, `player.download.cellularHold`, `player.download.hotspotHold`,
`player.download.lowDataMode` and `player.chapter.2.retry` (after opening the panel) are verified
by `DownloadStatusUITests` (`-stubDownloadStates` with a `-stubPath*` argument, the stub book opened
from the Library).

Speed itself (the requested `rate`/`defaultRate` across pause, seek and files) is unit-tested in
`PlayerSpeedTests`; the seeded books play real audio since #147, but no UI test measures the rate.

**Not addressable:** there is no `player.root`. It overwrote the title, all the transport controls
and the chapter list. Wait on `player.close` or `player.transport.play` to know the screen is up.
It slides in, so let it arrive before tapping inside it (the UI tests wait for `player.close` to
reach the top quarter of the screen).

**Not implemented:** `player.cover`, and `player.progress` with its labels. The scrubber is a
composite (a track, a touch view and three `Text`s), so it needs identifiers threaded through the
component, not applied from the call site.

## Gotchas

- **Rows are in the panel.** Open it with `player.chapters` before reaching any `player.chapter.<n>`
  or `.retry`; a tap on a row closes the panel again. On a short screen a row can sit under the
  panel's bottom edge, so tapping it misses: scroll first with a slow drag that holds at the end
  (`test_tappingAChapter_ofABookNotLoaded_loadsIt`); a `swipeUp()` flings a 60-chapter list far
  past it.
- **The scrubber is book time, not chapter time.** The mockup's numbers ("17:12 … −28:07") read
  like a chapter scrubber; the spec keeps today's seek behaviour, so the times are the book's and
  the centre label names the chapter. An owner question, #227.

- **A chapter tap starts playback, even from pause, and can switch books.** Since #166's owner
  decision there is no `isPlaying` gate and no dimming: tapping a row of a book that isn't loaded
  loads it (the previous book stops) at that chapter. A UI test that taps a chapter therefore
  changes the loaded book; open the book you mean first. Every seed but *Seeded Missing Book*
  plays from the chapter (#147); on *Seeded Long Book* a chapter past the 13th starts past the end
  of the 14-minute audio. It makes sound: pause it afterwards.
- **The overlay stays hit-testable only while a book is presented** (`allowsHitTesting`). After a
  close, taps reach the tabs once the collapse finishes.
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
