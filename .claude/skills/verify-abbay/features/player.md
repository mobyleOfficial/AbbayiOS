# Player (the details screen)

`PlayerView` is the full-screen details screen, "Player A" of the Liquid Glass redesign (#166 G1):
a large cover, a left-aligned title block, the scrubber, the transport, and glass pills: speed and
volume on the left, chapters on the right, and Text between them with Read-along on (#192). The chapters open as a glass
panel over the cover (G2); the Text pill flips the cover's square to the text being read. It is **no longer a sheet**.
It is drawn inside `PlayerExpansionOverlay`, one panel above the tabs that grows out of where it
was opened (the tapped [library](library.md) cover, or the [mini player](mini-player.md)) and
collapses back there (#241). The overlay paints the background (the
book's cover tint fading to near-black) and adds a header on top: a glass close button (`player.close`) and a drag strip
(`player.grabber`, hidden from accessibility; it no longer draws a grabber bar).
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
  `player.close`, label *Close player*) on the left; the rest of the header is an invisible drag
  strip. The grabber bar it used to draw was removed (owner's ask during the read-along device
  test: ⌄ already shows how to close). No ⋯ button: there is nothing to put in it yet. Tapping ⌄
  collapses the screen into the bar, animated. Dragging the header strip, the button or the cover
  down collapses it under the finger. The strip is hidden from VoiceOver (a drag area only), so ⌄
  is the one *Close player* element; the panel
  also answers the escape gesture (two-finger Z). Collapse rules are in
  [mini-player](mini-player.md#sub-features).
- **cover:** `ArtworkView(book:cornerRadius: 14, shadow: true)`, as wide as the screen less 24 pt
  margins (up to 360 pt), square, with a soft shadow; no artwork shows the generic tile, as in the
  [media row](media-row.md). On a short screen it shrinks, staying square, so the title, scrubber,
  transport and pills keep their room. While the panel grows, the overlay draws a growing copy of
  the cover (from the bar's 36 pt slot, radius 8 → 14, the shadow from half-way; or from the whole
  tapped library cover) that lands exactly here, and the real cover is hidden until then. The
  player reports the drawn square, not the up-to-360 pt frame around it, so on a screen where the
  cover is narrower than 360 pt (iPhone 15: 345 pt) it doesn't land too tall and snap (#254). The
  growing copy decodes its artwork once (`ArtworkView.decoded`), so it doesn't stutter on a device.
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
  (`speed.preset.<n>`; one row of equal glass capsules, the selected one solid malachite, and
  the row scrolls sideways when large text doesn't fit, #166 G7), and *Set as default for new books* (`speed.setDefault`, disabled and
  relabelled when the speed already is the default). The speed is **per book**: on the loaded book
  it applies at once (`Player.setPlaybackRate`); on another book it is remembered for when it plays.
  The player applies it through the one `AVQueuePlayer`'s `defaultRate`, so it holds across pause
  and resume, seeks and chapter-file advances, and publishes it to Now Playing.
- **volume:** Abbay's **own** volume, a gain on its one `AVQueuePlayer` (`player.volume`), never the
  system volume. On the Mac (the iPad app on Apple Silicon) the book can sit under a call, which the
  system volume would dim too; on iPhone and iPad it is a level inside the hardware buttons' volume.
  An icon-only glass pill right of the speed (`player.volume`, label *Book volume* / *Volume do
  livro*, value e.g. *60%*): `speaker.wave.3.fill` with the level as its variable value (the waves
  fill in by thirds at a constant width), `speaker.slash.fill` at 0%, white at 100%, malachite
  below it (as the speed pill is away from 1.0×) and red (`maximumRed`) above it. A tap raises a **vertical glass capsule** above
  it (`player.volume.slider`, `VolumeSlider`): the percent on top, a white fill to drag (a touch
  anywhere on the track sets the level there), the speaker at the bottom. It grows up out of the pill
  (only fades with Reduce Motion), is centred over it and kept on screen, shorter on a short screen
  (`VolumeSliderLayout`). No dim; a tap anywhere else, or the pill again, closes it. Levels are
  **0–200%** in 5% steps (#297): 0–100% fills the bottom two thirds of the track, 100–200% is
  squeezed into the top third, past a white notch at 100% that a drag sticks to
  (`BookVolume.stickiness`, a light haptic tick on landing there). Past 100% the whole fill, the
  percent and the speaker turn red, and the **boost** is on: the queue player stays at
  `volume` 1 and `VolumeBoost` multiplies the samples through an `MTAudioProcessingTap` on every
  item (imported files and each LibriVox chapter), with a soft `tanh` limiter past 0.8 so loud
  passages are squashed, not clipped. At or below 100% the tap leaves the samples untouched; an
  item it can't read (no audio track, not 32-bit float) plays unchanged. **One level for the whole app**, not per book: it holds across books, chapter files,
  pause and launches (`AppSettings.volume`, `abbay.settings.volume`, default 100%), and applies to
  CarPlay playback too, which has no control of its own. VoiceOver: the pill and the capsule are
  both adjustable (swipe up/down, 10% a step, through 200%), so the capsule never needs opening; the capsule also
  closes on the escape scrub. Not in the mini player or Now Playing.
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
  clipped to the track's capsule (near the start it hugs the rounded end, no stray line; #256)
  (a white thumb while dragging), and under it the elapsed time, the **current chapter's name**
  (centre, truncating) and the time remaining with a minus sign, in compact form ("17:12",
  "−1:05:09"). A touch anywhere along the track scrubs. While the finger scrubs, and until the
  clock reports the seek, the slider shows the scrubbed time, so it doesn't jump back for a tick.
- **resume-prompt:** (#299) after a chapter tap that resumed partway into the chapter, a glass
  capsule over the bottom of the cover (above the title) says *Resumed at 3:20* (`player.resumePrompt`;
  pt-BR *Retomado em 3:20*; the time is book time, as the scrubber shows) with **Start over**
  (`player.resumePrompt.startOver`, `arrow.counterclockwise`; pt-BR *Recomeçar*). Start over plays
  the chapter from its beginning, whatever was saved for it (`PlayerViewModel.restartChapter`; the
  shown book not loaded: loaded at the chapter's start first). The prompt goes after 6 s
  (`ResumePrompt.duration`) or on Start over, never shows under the open panel, and only on its own
  book's player. Nothing else on the screen moves. No prompt when the chapter starts at its start
  (never started, played through, within 1 s of it) or was already playing. The state is
  `PlayerPresentation.resumePrompt`, set by the panel's tap (`selectChapter` returns it). VoiceOver
  announces the message. CarPlay and Siri resume without a prompt. Evidence: `-seedPlayableBook`
  (3:20, chapter 2 starts 2:24) → Play → chapter 4 (no prompt) → chapter 2 → *Resumed at 3:2x* →
  Start over → playing from ~2:24.
- **read-along (#192, experimental; its own page is [read-along](read-along.md)):** with Read-along on in [Settings](settings.md) (iOS 26+ with an
  engine that runs here: `ReadAlongCenter.isAvailable`), a **Text pill** (`player.text`, *Text* / *Texto* with a
  `text.quote` icon) sits between speed and Chapters, the three spread across the row. A tap flips
  the cover's square to the text (`player.readAlong`, `ReadAlongView`), like lyrics in Apple Music,
  with a short cross-fade; nothing else on the screen moves. While the text shows, the pill reads
  *Cover* / *Capa* with a `photo` icon and VoiceOver reads it *Show cover* / *Mostrar capa*; a tap
  flips back. Whether the
  text shows is remembered app-wide (`AppSettings.readAlongShowsText`): it stays up across books,
  closing and reopening, and launches. **With Read-along off the pill row and the screen are exactly
  as before** (pixel-compared, task 8).
  - **the square:** the cover's frame and 14 pt radius, a dark fill (black 28%). The expansion's
    growing cover still lands on it (the square reports its frame), and the text shows once it has
    landed. The lines scroll in it with the current one kept in the middle: the current line white
    and semibold with the spoken word in malachite, lines already read 35% white, upcoming ones 55%;
    the top and bottom edges fade. It follows playback (polled every 0.1 s from the player,
    `PlayerViewModel.liveBookTime`), the saved position for a book that isn't loaded, and the
    scrubber while a finger drags it (no transcription starts under the finger: the text follows
    what is already covered, and a run starts where it lifts). Lines are `player.readAlong.line.<n>` (position in the
    transcript); each is a button to VoiceOver with the hint *Plays from this line* / *Toca a partir
    desta linha*; the current one has the selected trait, so VoiceOver can find it, and nothing is
    announced as it moves. **Reduce Motion:** the text jumps line to line without scrolling, and no
    word is highlighted.
  - **tap a line:** seeks to its start (`PlayerViewModel.seek`). On a book that isn't loaded it does
    nothing: it never loads or plays the book.
  - **language label:** a glass capsule in the bottom-leading corner (`player.readAlong.language`,
    *English ▾*, VoiceOver *Text language* / *Idioma do texto* with the language as its value), once
    the language is known. Its menu lists the languages iOS can transcribe by name, with the region
    only where two share a language (*English (United Kingdom)*), in the in-app language; the current
    one has a check. Picking one discards the book's text and transcribes again in it.
  - **expand button:** a glass circle in the bottom-trailing corner, opposite the language label
    (`player.readAlong.expand`, VoiceOver *Full screen* / *Tela cheia*): the same text over the whole
    window (`player.readAlong.fullScreen`, both panes when split), with the language label,
    play/pause (`player.readAlong.playPause`) and collapse (`player.readAlong.collapse`) along the
    bottom. Both corner controls **stay put under the open chapter panel** (their glass is a
    container of their own, not the player's, so it composites with the square and the panel draws
    over it; a tap there reaches the panel), are left out of the hierarchy while the player grows or
    shrinks (they fade in as it lands), and after 3 s with no interaction (a tap on the square brings them back without seeking; never
    while VoiceOver runs, the menu is open or the text isn't ready).
    See [read-along](read-along.md) *full screen*.
  - **messages** (`player.readAlong.status`), centred, a spinner while something is under way:
    *Preparing text…*, *Downloading the English speech model…*, *Text isn't available in X.*, *The
    audio must be downloaded first to show its text.* (a LibriVox chapter not on the device), *The
    audio file must be on this iPhone to show its text.* (an imported file that isn't), *Couldn't
    make the text.* (pt-BR in the catalogue). Before speech the next line waits dimmed; a long
    stretch with no speech (next line over 30 s away) shows ♪, VoiceOver *No speech here*; see
    [read-along](read-along.md).
    The text appears by itself once the chapter being played finishes downloading.
  - **when it runs:** only while the text is on screen. The square stops its session when it leaves
    the screen (the pill flips back, the player closes, Read-along is turned off) and when the app
    leaves the foreground, and shows it again when the app comes back or the screen follows another
    loaded book.
  - **while the text shows, the cover's collapse handle stands aside** (see
    [mini-player](mini-player.md)): a drag on the text scrolls it rather than collapsing the player;
    the header and ⌄ still collapse.
  - **landscape and split:** the text takes the cover's place in each layout (leading side in
    landscape).
- **chapters-pill:** the right glass pill (`player.chapters`, *☰ Chapters* / *Capítulos*) opens the
  chapter panel; while it is open it shows *✕* and its label is *Close chapters*. **A book with no
  chapter markers (a plain MP3) has no pill**, so there is no "No chapters" message on this screen
  any more (`player.chapters.empty` is gone). With the experimental *Find chapters* switch on, an
  **imported** book without chapters shows **Find chapters** (`player.findChapters`) in its place,
  then its progress while the audio is searched; chapters found replace it with this pill, and the
  panel ends with *Remove found chapters* (`player.chapters.removeFound`). See
  [find-chapters](find-chapters.md).
- **pill-row-fit:** with Read-along on, four pills share the row. The speed pill never shrinks
  (`fixedSize`: it read *1…* on a 393 pt iPhone before). The pills' side padding is 12 pt, so all
  four keep their words on a 393 pt iPhone in en and pt-BR, and on a 375 pt iPhone SE in en. When
  the row still runs short (pt-BR on the SE, a long speed like *1.75×*, larger text), the Text
  pill and then Chapters (`layoutPriority(1)`) show only their icon (`PlayerPill.collapsesToIcon`,
  a `ViewThatFits`); their buttons keep their VoiceOver labels. Evidence: `-seedLibrary
  -seedPlayableBook -resetSettings -seedReadAlong`, open the book, look at the row.
- **landscape (#270):** at a compact height (an iPhone in landscape), the cover fills the height on
  the leading side, and the title, scrubber, transport and pills stack on the trailing side
  (`verticalSizeClass == .compact`). The expansion's cover lands on that cover frame, and the chapter
  panel floats above the pills as in portrait. The panel is placed from the pills on screen (an
  anchor preference, `PillsAnchorKey`), not a stored frame: after turning the phone with the player
  open, a stored portrait frame put it over the pills and off the screen (#275).
- **adaptive (#255):** on a split window ([adaptive-layout](adaptive-layout.md)) the same `PlayerView`
  is a pane beside browsing under a ✕ (`player.close`), with no grabber or expansion, and its
  Chapters pill opens the chapters as a pane in browsing's place instead of the panel. Whether the
  chapters are open is `PlayerPresentation.isShowingChapters`, so it survives a fold or a resize. The
  full-screen player pads its content by the window's side insets (the folded Duo's status strip).
- **chapter-panel:** (#166 G2, `ChaptersPanel`) a glass panel (`abbayGlass` in a 26 pt rounded
  rectangle, tinted 35% black) that grows from the pill's corner and floats over the cover, above
  the pills, with a faint dim behind it. Nothing else on the screen moves. It spans the width less
  40 pt on the left and 16 on the right, and is up to 440 pt tall (about eight rows), less on a
  short screen, never less than `PlayerView.minChapterListHeight` (224 pt) on any iPhone (#203).
  **Below the cap it is as tall as its content:** on iOS 18 and later the list reports its real
  content height (`onScrollGeometryChange`, `ChaptersPanel.onListHeight`), so a three-chapter book's
  panel ends under its last row; the first frame, and iOS 17 always, use the old estimate (rows ×
  58 pt, scaled, plus the header and the found-chapters footer). The measurement is kept per book,
  chapter count and footer (`PanelListHeight`).
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
    the header, `ChaptersPanel.closesOnDrag`). A drag on the list scrolls it, even at its top
    (#229). Animated with a
    spring; Reduce Motion fades it instead of growing it.
  - the list no longer collapses the player: the chapter list's drag-to-collapse from its top
    (`ExpansionListCollapse`, `ListCollapseModifier`, iOS 18+) was deleted. The header still
    collapses the player exactly as before.
- **chapter-list-gating:** none any more (owner decision, #166). **Tapping a chapter always plays
  that chapter of the book the screen shows**, playing or paused, and the rows are never dimmed
  (they were dimmed to 50% while not playing, and the tap did nothing then).
  `PlayerViewModel.selectChapter`:
  - the shown book is loaded: `Player.playChapter(at:)` seeks to the chapter **where it was left**
    (see *chapter-resume*) and plays; a tap on the chapter already playing just plays on;
  - another book (or none) is loaded: the shown book is loaded first with `Player.play`, at that
    chapter's resume point (`Player.resumeTime(ofChapter:in:)`) rather than the book's saved
    position, then `playChapter(at:)`. The screen then follows it as the loaded book;
  - the shown book doesn't load (no file, offline and not downloaded, no audio session):
    `Player.play` reports why, as Play does, and nothing seeks the loaded book on its behalf.
    (Before the gate, a tap seeked the *loaded* book: the wrong chapter of the wrong book.)
- **chapter-resume:** (#299) every chapter remembers where listening got in it, so jumping to
  another chapter and back picks up where it was left, not at its start.
  - saved: `ChapterDataModel.resumeOffset` (seconds from the chapter's start; optional, model
    version 3; a chapter saved before #299 reads `nil`, never started). Written by
    `SavePlaybackPositionUseCase` with the book's position at every save (every 10 s while playing,
    pause, book switch, backgrounding), and before every chapter jump: a chapter tap, Next or
    Previous chapter.
  - played through: a chapter that plays on into the next one is saved at its full length
    (`ChapterCompletion`, from the 1 s ticks; a seek across the boundary doesn't count). The
    book's last chapter, with no next one, is saved at its full length when the book ends
    (`Player.bookDidEnd`: a single file's `AVPlayerItemDidPlayToEndTime`, a LibriVox book's
    `onBookEnd`).
  - a tap on the chapter already loaded plays on from the playhead, unless the playhead is in its
    last 5 s or past (`ChapterModel.isFinished(at:)`, e.g. the book ended there): it starts over.
  - resumed (`ChapterModel.resumeTime`): at the saved offset; from the start when never started,
    played through, or left in its last 5 s (`ChapterModel.finishedTolerance`). Read from the
    saved book (`LoadChapterResumeUseCase`), not a screen's copy.
  - who resumes: a chapter tap in this panel, CarPlay's chapter list and Siri's
    *Play chapter N*. **Next and Previous chapter still go to a chapter's start**, and Previous
    more than 15 s in restarts the chapter. On this screen the *resume-prompt*'s Start over
    is the way to hear one from the beginning; in the mini player, its swipe right.
  - the book's own position (Continue card, library progress, Play) is unchanged: the last place
    listened, whatever chapter it's in. The chapter list's *finished* rows are still "before the
    current chapter".
  - evidence: play chapter 1 to ~0:40, tap chapter 3, tap chapter 1 → the scrubber reads ~0:40
    into chapter 1, not 0:00. Unit: `ChapterResumeTests`, `ChapterProgressPersistenceTests`
    (version 1 and 2 stores migrate through `DataStack`), `PlayerViewModelChapterTapTests`.
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
  `currentChapter`, so it re-renders once per chapter. The read-along square, while it shows,
  polls the player every 0.1 s inside itself (a `TimelineView`), and its lines redraw only when the
  line or word to highlight changes. The open chapter panel reads the clock, but
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
$B tap library.row.0.title && $B wait player.close       # grows out of the cell's cover (#241)
$B tap player.transport.play                              # a seeded book loads and plays (the Debug fixture's audio)
$B tap player.transport.forward && $B snapshot
$B tap player.speed && $B tap speed.preset.1.5 && $B swipe down   # player.speed value "1.5×"
$B tap player.volume && $B wait player.volume.slider    # the glass capsule above the pill; value "100%"
$B drag player.volume.slider down && $B tap player.title  # dims the book (pill value e.g. "50%", green); a tap outside closes it
$B drag player.volume.slider up                           # to the top: "200%", the whole fill and the pill red
$B tap player.chapters && $B wait player.chapters.panel  # the glass chapter panel, at the current chapter
$B tap player.chapter.2                                   # plays chapter 3 of the shown book, paused or not (loads it if needed); closes the panel
$B tap player.close && $B wait library.list
$B launch -seedLibrary -seedPlayableBook -resetSettings -seedReadAlong   # Read-along on, stub text every 4 s
$B tap library.row.<n>.title && $B tap player.text && $B wait player.readAlong.line.0   # the text in the cover's square
$B tap player.readAlong.line.5                            # seeks there when the book is loaded; nothing otherwise
$B tap player.readAlong.language                          # the menu: English, Portuguese
$B tap player.readAlong.expand && $B wait player.readAlong.fullScreen   # over the whole window
$B tap player.readAlong.collapse                          # back to the square
$B drag player.close down                                 # planned: collapse under the finger (the grabber is not addressable)
```

**Verified** (`AccessibilityIdentifierTests`, `MiniPlayerUITests`):
- `player.title`
- `player.transport.{back,play,forward}` and `player.speed`
- the speed sheet's `speed.{value,increase,decrease,setDefault}` and `speed.preset.<n>`
  (`SettingsUITests.test_speedSheet_*`), and the forward button's label following Settings
  (`test_changingSkipForward_updatesThePlayersButton`)
- the volume (`VolumeUITests`): `player.volume` reads *Book volume*, *100%*; a tap shows
  `player.volume.slider` centred above it; a drag from near its top to its middle dims the book
  (40–95%: 0–100% is two thirds of the track), and the pill follows; a drag to the top reads
  *200%* on both; a tap on the title or a second tap on the pill closes it, keeping the level;
  VoiceOver's decrement/increment on the pill moves 10% without opening the capsule
  (`AccessibilityActions.decrement`/`increment`). The gain itself (applied at launch, across books
  and chapter files, never resuming a paused book; past 100% the player stays at 1 and the boost
  gains the rest) is unit-tested in `PlayerVolumeTests`, the track mapping, notch and limiter in
  `BookVolumeTests` (and the tap attaching to a real m4b in `VolumeBoostAttachTests`), the
  capsule's placement and the VoiceOver step in `VolumeSliderTests`, the stored level in
  `AppSettingsTests`. No test measures the audio's loudness.
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
- read-along (`ReadAlongUITests`, iOS 26+, `-seedReadAlong`): no `player.text` with Read-along off;
  `player.text` flips to `player.readAlong` with `player.readAlong.line.0` and back; the selected line
  moves on while playing; a line tap on a book that isn't loaded leaves *Play*; a line tap on the
  loaded book moves the elapsed time to the line's start; `player.readAlong.language` opens a menu
  with *English* and *Portuguese*; with `-forceReduceMotion` one line is selected; the text stays up
  after closing and reopening; in landscape `player.readAlong` sits on the leading side, clear of
  the transport; `player.readAlong.expand` shows `player.readAlong.fullScreen` over the whole window
  (an iPad's split too), its play/pause drives playback, collapse brings the square back, and the
  label and the expand button stay where they are under the open chapter panel (a tap at either
  reaches the panel: no menu, no full screen) and work once it closes; the corner controls hide after 3 s
  idle and a tap brings them back (`ReadAlongImmersionUITests.swift`). The menu's naming is unit-tested in `ReadAlongViewTests`, `liveBookTime` in
  `PlayerViewModelTests`. Not driven by a UI test: the status messages other than the stub's quick
  *Preparing text…*, the scene-phase stop, and VoiceOver itself.
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
  the centre label names the chapter. An owner question, #228.

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
