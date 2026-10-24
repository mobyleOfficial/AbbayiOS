# Mini player

`MiniPlayerView` is the one-row bar that shows the book loaded in the player. It appears on both
[tabs](tabs.md) whenever a book is loaded (`PlaybackState.loadedBook`), and the details screen
([player](player.md)) expands out of it under the finger. It replaces the old floating player.

## Sub-features

- **presence:** shown while a book is loaded and the details screen isn't settled open. It is
  hidden once the screen has settled open, and back as soon as a close or a collapse drag starts.
  Playback started anywhere shows it: a row, the details screen, a LibriVox page's Play, Siri or
  CarPlay. Deleting the loaded book removes it (`PlaybackCenter.unload()`).
- **placement:**
  - **iOS 26.1+:** the system tab bar's `.tabViewBottomAccessory(isEnabled:)`. The system sets the
    height (about 48 pt) and the capsule shape (`MiniPlayerAccessory`).
  - **iOS 17.0–26.0:** `MiniPlayerDock`, 56 pt with rounded corners, docked right above the
    hand-built tab bar. It slides in from the bottom.
  - On both paths the list content ends above the bar (`test_lastRow_isNotCoveredByMiniPlayer`).
- **content:**
  - the cover (40 pt)
  - the title
  - *Chapter N · X min left* (`miniPlayerSubtitle`), or the time left in the book when it has no
    chapters
  - play/pause (`miniPlayer.playPause`)
  - a 2 pt line along the bottom edge for progress within the chapter, or within the book without
    chapters (`miniPlayer.progress`)

  The background is tinted from the cover (`CoverTint`, cached per book).
- **tap:** opens the details screen on the loaded book (`presentation.open`).
- **drag up:** a vertical drag expands the details screen under the finger, starting from the bar's
  frame. Released past 30% of the travel, or flicked up faster than 800 pt/s, it settles open.
  Otherwise it settles back into the bar. A slow drag animates slowly, and grabbing mid-spring
  continues from what is on screen. See `ExpansionMath`.
- **swipes:** a horizontal drag past 40 pt that is more horizontal than vertical acts on release:
  - **left:** the next chapter (`skipToNextChapter`)
  - **right:** back to the start of the current chapter (a seek, not "previous chapter")

  On the last chapter, or in a book without chapters, nothing happens and the bar gives a light
  haptic. The text nudges toward the swipe either way. The axis is decided on the gesture's first
  event.
- **accessibility:** the title and subtitle are one element (`miniPlayer.bar`, a button). Its
  default action opens the details screen. Its named actions are *Open player*, *Next chapter*
  and *Restart chapter*, so VoiceOver can do everything the gestures do. The progress line carries
  a percentage value and `.updatesFrequently`.
- **expansion:** `PlayerExpansionOverlay`, one panel above the tabs. Its frame grows from the bar's
  frame to the full screen as `PlayerPresentation.progress` goes from 0 to 1.
  - The corner radius goes from the bar's to 0.
  - The cover grows from 40 pt to the details screen's cover.
  - The bar's face fades out over the first 30%, and the details screen fades in over the last 70%.
  - Opened with nothing visible to grow from (a row tap with nothing loaded), it grows from a
    56 pt strip along the bottom edge.
- **collapse:** a drag down from the details screen's grabber header (`player.grabber`), its close
  chevron or its cover follows the finger back into the bar, under the same 30% / 800 pt/s rule.
  `player.close` (the chevron) collapses it animated. While the panel is moving, a drag anywhere
  on it continues the motion.
  - **iOS 18+:** a downward drag that starts while the chapter list rests at its top also
    collapses, and the list doesn't scroll for that gesture. Any other list drag scrolls
    (`onScrollGeometryChange`).
  - **iOS 17:** only the header and the cover collapse. iOS 17 has no scroll-offset API (Ruling 13).
  - The collapse lands on the bar's resting frame, even after Play loaded the book while the screen
    was open (`test_collapseAfterPlayingInDetails_landsOnTheBar`).
- **reduce-motion:** with Reduce Motion on, open and close are an opacity cross-fade between the
  same end states, with no frame, corner or cover interpolation. This is only checked by hand.
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
$B launch --seed-library
$B tap library.row.0.play && $B wait miniPlayer.bar     # a seeded book loads (no audio), the bar shows
$B tap miniPlayer.bar && $B wait player.close            # details screen, grown from the bar
$B tap player.close && $B wait miniPlayer.bar
$B drag miniPlayer.bar up                                # planned: finger-tracked expansion
$B drag player.grabber down                              # planned: collapse into the bar
$B a11y-action miniPlayer.bar "Next chapter"             # planned: VoiceOver custom action
```

**Verified** (`MiniPlayerUITests`, `AccessibilityIdentifierTests`):
- `miniPlayer.bar`, `miniPlayer.playPause` and `miniPlayer.progress`
  (`test_miniPlayer_identifiersResolve`; the bar's label carries the title and *Chapter 1*)
- tap to open and hidden-while-open (`test_tappingMiniPlayer_opensDetails`)
- drag up, short drags settling back, slow drags both ways
- grabber collapse (`player.grabber`) and list-at-top collapse (iOS 18+)
- the last row clearing the bar (`-seedFillerBooks`)
- the bar on both tabs after Play on the stub LibriVox book
  (`test_playFromDetail_opensPlayer_thenLibraryShowsMiniPlayer`)

The UI suite runs on iOS 26.4 (accessory) and 18.5 (dock).

**Unit-tested only:**
- swipes and their no-op haptic (`MiniPlayerActionsTests`)
- the subtitle and progress maths
- the settle thresholds and the release-velocity window (`ExpansionMathTests`, `ExpansionDragTests`)
- presentation state (`PlayerPresentationTests`)

The named accessibility actions and Reduce Motion are not exercised by any test.

## Gotchas

- **A seeded book loads without audio.** Its row's play button makes the player announce the
  book, which is all the bar needs, but nothing plays, so the clock doesn't move. The progress
  line and the time left stay at the saved position.
- **The playing glyph trusts buffering.** `Player.isPlayingPublisher` counts *waiting* as playing
  only while buffering (`.toMinimizeStalls`, `.evaluatingBufferingRate`), not with no item to play.
  A book whose audio can't load shows *play* rather than a stuck *pause* (Ruling 12,
  `PlayerPlayingStatusTests`). Expect a brief *play* flash before buffering starts.
- **Drag velocity is measured by SwiftUI** in the simulator, and synthesized drags can report ~0 at
  the lift. `ExpansionMath.releaseVelocity` also looks at the 60 ms before the release.
- **The bar's frame is snapshotted at drag start** (Ruling 6). The accessory jumps about 70 pt when
  the tab bar hides, so the overlay never re-reads it mid-drag.
- iOS 17 can't collapse from the chapter list. Grab the header or the cover.
- A device check of the list-at-top bounce interaction on iOS 18+ is left to the owner.
