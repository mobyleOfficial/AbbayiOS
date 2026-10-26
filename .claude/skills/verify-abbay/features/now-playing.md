# Now playing

`NowPlayingManager` — the lock screen, Control Center and remote-command surface. Also the state
that Siri's Pause / Next / Previous intents gate on, which makes it load-bearing well beyond its
own UI.

## Sub-features

- **info-publishing:** `updateNowPlaying(for:currentTime:isPlaying:)` builds the
  `MPNowPlayingInfoCenter` dictionary — title, artist (falling back to album), album, duration,
  elapsed time, playback rate, artwork — and sets `playbackState` explicitly.
- **chapter-reporting:** when the book has chapters it also publishes `AlbumArtist` as
  *"Chapter N of M"*, plus `ChapterNumber`, `ChapterCount` and audio media type.
- **remote-commands:** `setupRemoteCommandCenter()` runs once from `init`, wiring the system's
  play/pause/skip controls back into the player.
- **skip-intervals:** the skip commands' `preferredIntervals` and the amounts their handlers jump
  (`skipBackward()` / `skipForward()`) come from [Settings](settings.md) through
  `setSkipIntervals(backward:forward:)`, applied at launch and on every change (default 15 s).
- **speed:** `MPNowPlayingInfoPropertyPlaybackRate` is the book's real speed while playing (0 when
  paused) and `DefaultPlaybackRate` is the book's speed, so the lock screen's clock runs at the right
  pace. `changePlaybackRateCommand` offers the speed presets and sets the loaded book's speed
  (`changePlaybackRate(to:)` → `Player.setPlaybackRate`). Changing the speed in the app pushes the
  info at once rather than waiting for the next tick. CarPlay's Now Playing rate button (#150) shows
  this rate and cycles the presets through the same `Player.setPlaybackRate` (see
  [carplay](carplay.md) *rate-button*).
- **current-audio:** `currentAudio` is the read-only view of the loaded model. Written only by
  `Player.play` on every play (`NowPlayingManager.setPlayer(_, currentAudio:)`) and dropped by
  `clearNowPlaying()`. Consumed by `PauseAbbayIntent`, `NextChapterIntent`,
  `PreviousChapterIntent`, `PlayChapterIntent` and `ChapterEntity.currentBook()`.
- **clearing:** `clearNowPlaying()` nils the system dictionary. Called from `Player.cleanup()`.
- **toggle:** `togglePlayPause()` (the lock screen's, Control Center's and CarPlay's play/pause
  toggle) pauses when `Player.isPlaying(_:)` says playing, plays otherwise.

## How to get to it (user POV)

Start playback, then lock the device or open Control Center. Also the CarPlay now-playing screen,
which reads the *same* info and handlers — one integration serves both.

## Driving it with abbay-ctl

Not drivable: the lock screen and Control Center are system UI outside the app's process. Verify
through the state the app controls instead.

```bash
$B tap library.row.0.play
$B nowplaying                                 # planned: dump MPNowPlayingInfoCenter via a debug hook
$B appgroup get abbay.diagnostics.v1          # intent gates record their decisions here
```

The honest coverage for this feature is unit tests over the dictionary construction plus the
`currentAudio` lifecycle, not UI automation. Assert on `playbackRate` and elapsed time, not merely
that a handler ran.

## Gotchas

- **Behavior change on the tabs + mini player branch: buffering counts as playing.**
  `Player.isPlaying(_:)` now uses the same mapping as `isPlayingPublisher`
  (`Player.isPlaying(status:reason:)`): `.playing`, or `.waitingToPlayAtSpecifiedRate` with a
  buffering reason (`toMinimizeStalls`, `evaluatingBufferingRate`). So the toggle pressed while
  the audio buffers **pauses** it, matching the pause icon the app shows; before, it called `play`
  again. Waiting with `.noItemToPlay` (audio that can't load) still reads as not playing, so the
  toggle plays. Pinned by `NowPlayingManagerTests.test_togglePlayPause_whileBuffering_pauses`.

- **The playback gate is refreshed on every `play()` and dropped by `clearNowPlaying()`** (fixed for
  #93 in #98): after `Player.cleanup()` the intents see no loaded book, and replaying the
  already-loaded book re-syncs `currentAudio`. Earlier versions of this map described both as bugs;
  they are covered by unit tests, not by driving the app.
- **Multi-file (LibriVox) books are published as one book, by assumption.** `NowPlayingManager` is
  unchanged on this branch; it reads `duration`, the elapsed `currentTime` the player passes and
  `AudioModel.currentChapter(for:)`, and a LibriVox book keeps those in book time (cumulative chapter
  `startTime`s; the periodic observer publishes `MultiFileQueue.bookTime`). So the lock screen should
  show total duration, book-wide elapsed time and "Chapter N of M". **Nothing verifies this on a
  lock screen or in a test of `NowPlayingManager` with a LibriVox model**; treat it as expected, not
  proven. The same holds for remote skip commands, which seek in book time through
  `Player.forward/backward`.
- `playbackState` must be set explicitly; the system does not reliably infer it from the audio
  session, and several reported Control Center "stuck on pause" bugs trace to exactly that. Abbay
  does set it (`updateNowPlaying`) — keep it that way.
- `print` statements with emoji ship in Release here (`updateNowPlaying`, `clearNowPlaying`, remote-command setup). Same in
  `Player`, `URL+SecurityScoped` and `DataStack` — roughly 30 in total across the app.
- Simulator and device diverge on remote-command behaviour. Treat simulator results as indicative
  only.
