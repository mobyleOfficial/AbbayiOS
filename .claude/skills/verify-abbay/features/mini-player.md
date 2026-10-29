# Mini player

`MiniPlayerView` is the one-row bar that shows the book loaded in the player. It appears on both
[tabs](tabs.md) whenever a book is loaded (`PlaybackState.loadedBook`), and the details screen
([player](player.md)) expands out of it under the finger. It replaces the old floating player.

## Sub-features

- **presence:** shown while a book is loaded and the details screen isn't settled open. It is
  hidden once the screen has settled open, and back as soon as a close or a collapse drag starts.
  On a split window ([adaptive-layout](adaptive-layout.md)) it stays unless the player pane shows the
  loaded book, and a tap or a drag up opens the pane (`MiniPlayerVisibility`).
  Playback started anywhere shows it: a row, the details screen, a LibriVox page's Play, Siri or
  CarPlay. Deleting the loaded book removes it (`PlaybackCenter.unload()`).
- **placement:**
  - **iOS 26.1+:** the system tab bar's `.tabViewBottomAccessory(isEnabled:)`. The system sets the
    height (about 48 pt) and the capsule shape (`MiniPlayerAccessory`).
  - **iOS 17.0–26.0:** `MiniPlayerDock`, 56 pt with rounded corners, docked right above the
    hand-built tab bar. It slides in from the bottom.
  - On both paths the list content ends above the bar (`test_lastRow_isNotCoveredByMiniPlayer`).
- **content:**
  - the cover: 36 pt, inset from the bar's edges (12 pt from the leading edge, about 6 pt above and
    below in the 48 pt capsule, 10 pt in the 56 pt dock) with all four corners rounded 8 pt (#242).
    Its slot is `MiniPlayerMetrics`, shared with the expansion overlay, so the bar → player cover
    animation starts exactly on it.
  - the title
  - *Chapter N · X min left* (`miniPlayerSubtitle`), or the time left in the book when it has no
    chapters. Whole minutes rounded up; zero units are dropped, so exactly one hour reads
    "1 hr left" / "1 h restante", not "1 h e 0 min" (#152). Nothing left is plural in pt-BR
    ("0 min restantes"). `-seedTimeLeftEdges` seeds *Seeded Hour Book* to show it.
  - play/pause (`miniPlayer.playPause`)
  - a 2 pt line along the bottom edge for progress within the chapter, or within the book without
    chapters (`miniPlayer.progress`)

  The background is tinted from the cover (`CoverTintBackground`). The tint is computed off the
  main thread the first time a book shows, and cached per book (by URL, or by artwork for a book
  without one). Until it lands, a frame or two, the background is `onyx`.
- **tap:** opens the details screen on the loaded book (`presentation.open`) with the same spring
  expansion as the drag (#241; before, a tap snapped to the end state: the panel was inserted with
  its progress already at 1). An open from closed puts the panel on screen at 0 and starts the
  spring once it appears (`PlayerPresentation.stageDidAppear`, with a 100 ms fallback when nothing
  renders it).
- **drag up:** a vertical drag expands the details screen under the finger, starting from the bar's
  frame. Released past 30% of the travel, it settles open; otherwise back into the bar. A flick
  of at least 800 pt/s decides by its own direction, even against the drag's: up opens, down
  closes. A slow drag animates slowly, and grabbing mid-spring
  continues from what is on screen. See `ExpansionMath`.
- **swipes:** a horizontal drag past 40 pt that is more horizontal than vertical acts on release:
  - **left:** the next chapter (`skipToNextChapter`; two quick swipes go two chapters, see
    [player](player.md#sub-features) *chapter-skips*)
  - **right:** back to the start of the current chapter (a seek, not "previous chapter")

  On the last chapter, or in a book without chapters, nothing happens and the bar gives a light
  haptic. The text nudges toward the swipe either way. The axis is decided on the gesture's first
  event.
- **accessibility:** the title and subtitle are one element (`miniPlayer.bar`, a button). Its
  default action opens the details screen. Its named actions are *Open player*, *Next chapter*
  and *Restart chapter*, so VoiceOver can do everything the gestures do. The progress line is
  labelled *Chapter progress* and carries a whole-percent value ("39%") and `.updatesFrequently`.
  The play/pause button reads *Play* or *Pause* (`PlayButtonView`, shared with the rows and the
  details screen; labelled since #144). On the details screen the glass ⌄ button is *Close player*
  and the panel's escape action (the two-finger scrub) closes it too.
- **expansion:** `PlayerExpansionOverlay`, one panel above the tabs. Its frame grows from its
  origin (`PlayerPresentation.origin`, decided by `ExpansionMath.origin`) to the full screen as
  `PlayerPresentation.progress` goes from 0 to 1. The origin is the tapped library cover (a grid
  cell or the Continue card, see [library](library.md)) while at least half of it is on screen,
  else the bar's frame, else the bottom strip. From a cover, the panel starts as that cover (its
  frame and radius) and the cover flies into the player's large cover; the bar's face isn't drawn.
  - The corner radius goes from the bar's to 0.
  - The background is the details screen's cover-tint gradient (#166 G1), with the bar's flat
    tint over it fading out with the bar's face: the same colour at the top, so the bar reads as
    one surface changing size. No `onyx` panel any more.
  - The cover grows from the bar's 36 pt slot (radius 8) to the details screen's cover (radius 14),
    its shadow appearing from half-way. From a library cover it grows from that whole cover (its
    radius: 10 for a cell, 8 for the Continue card).
  - The bar's face fades out over the first 30%, and the details screen fades in over the last 70%.
  - Opened with nothing visible to grow from (a LibriVox page's Play with nothing loaded), it
    grows from a 56 pt strip along the bottom edge.
- **collapse:** a drag down from the details screen's grabber header, its close button
  (`player.close`) or its cover follows the finger back into the bar, under the same 30% / 800 pt/s rule.
  `player.close` collapses it animated. While the panel is moving, a drag anywhere on it continues
  the motion. On every iOS version these are the only handles: the chapter list moved into the
  glass chapter panel (#166 G2), which closes itself and never collapses the player, so the
  list-at-top collapse (iOS 18+, `ExpansionListCollapse`) was deleted. The cover's collapse
  handle is drawn by the overlay above the details screen, so while the chapter panel is open
  over the cover it stops taking touches (`ExpansionGeometry.isChaptersOpen`, reported by
  `PlayerView`'s `onChaptersOpen`); otherwise it swallowed the panel's taps and drags there.
  - Opened from a library cover, the collapse (⌄ or a drag) lands back on that cover at its latest
    frame while it is still on screen; once it is gone (scrolled away, deleted, the Continue card
    showing another book) it lands on the bar, or the strip. A drag's travel is at least half the
    screen, so a cover near the top isn't hair-trigger (`ExpansionMath.travel`).
  - The collapse lands on the bar's resting frame, even after Play loaded the book while the screen
    was open (`test_collapseAfterPlayingInDetails_landsOnTheBar`). Released while the bar is still
    coming back with the tab bar, it follows the bar's frames and lands on the bar, not on the
    bottom strip. The UI tests check a collapse lands with the bar at rest along the bottom, taking
    touches, and where it was before the open (`assertCollapsedIntoBar`).
- **reduce-motion:** with Reduce Motion on, open and close are an opacity cross-fade between the
  same end states, with no frame, corner or cover interpolation: the panel is full-screen at every
  progress and only its opacity moves. `-forceReduceMotion` turns it on for a launch.
- **interruptions:** a gesture the system cancels (an incoming call) has no `onEnded`. The overlay
  settles any drag in flight when the scene goes inactive (`cancelInteractive`).

## Task 1 verdict (spike)

`ACCESSORY_HOSTS_EXPANSION = yes`
(`docs/superpowers/research/2026-10-23-tab-accessory-spike.md`): the bar can live in the iOS 26
accessory and drive the expansion overlay. The condition (Ruling 5) is that the drag's state lives
in models read only by small leaf views, never by the root or the accessory's body. The spike
showed that a gesture whose view re-renders stops receiving touches. That is why `BarDrag` and
`MiniPlayerSwipe` are plain classes and only the overlay reads `progress`.

## Hard rule: the bar does almost no work per tick

The bar's body reads `PlaybackState` only (play, pause, switch). Only `MiniPlayerSubtitle` and
`MiniPlayerProgressLine` read `PlaybackClock`, so a tick re-renders those two leaves. The
dock and the accessory read `loadedBook` and `isFullyOpen` only, so they never re-render per tick
or per drag frame.

## How to get to it (user POV)

Press play on any library row, or Play on a LibriVox details page, then look above the tab bar.

## Driving it with abbay-ctl

```bash
$B launch -seedLibrary
$B tap library.row.0.play && $B wait miniPlayer.bar     # a seeded book plays (the Debug fixture), the bar shows
$B tap miniPlayer.bar && $B wait player.close            # details screen, grown from the bar
$B tap player.close && $B wait miniPlayer.bar
$B drag miniPlayer.bar up                                # planned: finger-tracked expansion
$B drag player.close down                                # planned: collapse into the bar (the grabber has no a11y element)
$B a11y-action miniPlayer.bar "Next chapter"             # planned: VoiceOver custom action
$B launch -seedLibrary -seedPlayableBook                 # a real m4b, 200 s in (chapter 2)
$B launch -seedLibrary -forceReduceMotion                # the cross-fade expansion
```

**Verified** (`MiniPlayerUITests`, `AccessibilityIdentifierTests`):
- `miniPlayer.bar`, `miniPlayer.playPause` and `miniPlayer.progress`
  (`test_miniPlayer_identifiersResolve`; the bar's label carries the title and *Chapter 1*)
- tap to open and hidden-while-open (`test_tappingMiniPlayer_opensDetails`); a library cell and the
  Continue card open and close back (`LibraryGridUITests.test_cellTap_*`,
  `test_continueCard_tapOpensThePlayer_andCloseReturnsToTheCard`)
- drag up, short drags settling back, slow drags both ways
- grabber collapse (dragged from the grabber's position, found from `player.close`: the grabber
  is hidden from accessibility, see [player](player.md)); with the chapter panel open, a drag at
  its top closes only the panel and the header still collapses (`ChaptersPanelUITests`)
- the last row clearing the bar (`-seedFillerBooks`)
- the bar on both tabs after Play on the stub LibriVox book
  (`test_playFromDetail_opensPlayer_thenLibraryShowsMiniPlayer`)
- VoiceOver actions (`MiniPlayerAccessibilityUITests.swift`, `test_a11y_*`), performed the way
  VoiceOver does through `AbbayUITests/AccessibilityActions.swift` (a `tap()` would test the
  gestures instead):
  - the bar's named actions are exactly *Open player*, *Next chapter*, *Restart chapter*
  - the default action and *Open player* open the details screen
  - *Next chapter* moves to chapter 3 and *Restart chapter* back to 0% of chapter 2
    (`-seedPlayableBook`)
  - *Close player* is labelled, and activating it or the escape scrub collapses into the bar
  - the progress line's label and value (a few % into a seeded book's first chapter, which now
    plays from 0 s; about 39% on the playable one)
  - play/pause buttons have a label, which flips *Pause* to *Play*
- Reduce Motion (`-forceReduceMotion`): tap open, chevron close, drag open, grabber collapse and a
  short drag settling closed all land, and afterwards the bar, its play button and a library row
  take touches (nothing invisible left over the tabs).

The UI suite runs on iOS 27.1 and 26.4 (accessory) and 18.5 (dock). The 12 `test_a11y_*` tests
pass on 27.1, 26.4, 18.5 and 17.5 (#162, #129). On the iPhone Duo (the iOS 27.1 runtime's only
device) the details screen's chapter card is one row tall, and the chapter-list drag tests fail
there (#203).

**Unit-tested only:**
- swipes and their no-op haptic (`MiniPlayerActionsTests`)
- the subtitle and progress maths
- the settle thresholds and the release-velocity window (`ExpansionMathTests`, `ExpansionDragTests`)
- presentation state (`PlayerPresentationTests`): the pending open that starts at 0 and springs once
  the panel appears (#241)
- the origin decision, cover vs bar vs strip, on open and on close (`ExpansionOriginTests`,
  `PlayerPresentationOriginTests`), including Reduce Motion from a cover (a cross-fade)
- `-forceReduceMotion` itself (`DebugOverridesTests`), and the playable seed's chapters against
  the file (`UITestSeederTests`)
- the Reduce Motion cross-fade (`ExpansionAppearanceTests`): `ExpansionLayout` takes the panel's
  frame, corners, opacities and the cover's frame from `ExpansionMath.appearance` / `coverFrame` /
  `coverRadius`, and the tests sample every 5% (plus a spring's overshoot) to check that with
  Reduce Motion the panel is full-screen with square corners, the cover sits at its target, and
  only the panel's opacity moves (equal to the progress). A control asserts the same samples do
  interpolate without Reduce Motion. Views read Reduce Motion through `@ReduceMotion`, which
  applies `-forceReduceMotion` without depending on the environment (#185).

**Not automated:**
- the expansion from a tapped cover on screen: checked by eye from screen recordings (#241's PR:
  frames mid-open and mid-close from a cell, the Continue card and the bar).
- the cross-fade on screen: XCUITest only reads the screen once it is idle, so the rendered
  panel mid-transition is checked by eye. Snapping `simctl io screenshot` while
  `test_a11y_reduceMotion_dragsOpenCollapseAndSettle` runs on 18.5 shows a full-screen,
  half-transparent panel during the 120 pt drag and the collapse (#162). The decision behind it
  is unit-tested (above).
- a VoiceOver pass on a device: what is spoken, focus order, and the actions rotor itself (#161).

## Gotchas

- **A seeded book plays real audio** (#147): the Debug fixture, linked under the seed's name. The
  clock moves, so the progress line and the time left change while a test runs; pause it if the
  assertion needs a still position (as `loadPlayableBook` does). Only *Seeded Missing Book*
  (`-seedMissingFile`) loads without audio.
- **No Siri alert in UI tests** (#163): a launch with any `LaunchArgument` skips
  `requestSiriAuthorization`. Before, on a fresh simulator, the alert intercepted the first tap
  of the run (always `library.row.<n>.play` in `test_miniPlayer_identifiersResolve`); XCTest
  dismissed it when it was already up, but one that came up after its check swallowed the tap
  and the bar never appeared.
- **The playing glyph trusts buffering.** `Player.isPlayingPublisher` counts *waiting* as playing
  only while buffering (`.toMinimizeStalls`, `.evaluatingBufferingRate`), not with no item to play.
  A book whose audio can't load shows *play* rather than a stuck *pause* (Ruling 12,
  `PlayerPlayingStatusTests`). Expect a brief *play* flash before buffering starts.
- **Drag velocity is measured by SwiftUI** in the simulator, and synthesized drags can report ~0 at
  the lift. `ExpansionMath.releaseVelocity` also looks at the 60 ms before the release.
- **The bar's frame is snapshotted at drag start** (Ruling 6). The accessory jumps about 70 pt when
  the tab bar hides, so the overlay never re-reads it mid-drag.
- **XCUITest has no public API for accessibility actions.** `AccessibilityActions` goes through
  XCTest's private `XCAXClient_iOS` with VoiceOver's AX action numbers (2010 activate, 2013
  escape, 2021 custom). An Xcode update may move them; it throws naming the missing piece.
- Only the header and the cover collapse the player, on every iOS version (the chapter list is in
  the chapter panel since #166 G2).
