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
- **current-audio:** `currentAudio` is the read-only view of the loaded model. Written only by
  `Player.updatePlayItem` (`Player.swift:222`). Consumed by `PauseAbbayIntent`, `NextChapterIntent`,
  `PreviousChapterIntent`, `PlayChapterIntent` and `ChapterEntity.currentBook()`.
- **clearing:** `clearNowPlaying()` nils the system dictionary. Called from `Player.cleanup()`.

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

- **`clearNowPlaying()` does not reset `currentAudio` (#93).** It clears the system dictionary and
  leaves `model` set. After `Player.cleanup()` — which runs from `deinit` and
  `applicationWillTerminate` — the system believes nothing is playing while the intent gate still
  reports a loaded book. "Pause Abbay" then answers *"Paused."* with nothing playing.
- **`play()` only refreshes `currentAudio` when the URL changes.** `updatePlayItem` is inside
  `if url != self.url` (`Player.swift:125-127`), so replaying the already-loaded book never updates
  the gate. Combined with the above, staleness survives a cleanup/replay cycle.
- `playbackState` must be set explicitly; the system does not reliably infer it from the audio
  session, and several reported Control Center "stuck on pause" bugs trace to exactly that. Abbay
  does set it (`NowPlayingManager.swift:61`) — keep it that way.
- Three `print` statements with emoji ship in Release here (`:63`, `:68`, `:78`). Same in
  `Player`, `URL+SecurityScoped` and `DataStack` — roughly 30 in total across the app.
- Simulator and device diverge on remote-command behaviour. Treat simulator results as indicative
  only.
