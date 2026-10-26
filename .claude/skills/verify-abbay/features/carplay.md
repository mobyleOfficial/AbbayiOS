# CarPlay

`CarPlaySceneDelegate` — the library list, the now-playing template and the chapter list on a car
head unit. The entitlement is approved and this surface **ships**, but nothing automated reaches it and
two of its original bugs (#90, #95) are still open.

## Sub-features

- **connect:** `didConnect` stores the interface controller (and becomes its delegate), configures
  `CPNowPlayingTemplate.shared` (Up Next button enabled, titled *"Chapter selection"*, the rate
  button, self registered as observer), installs player observers, sets the library as root, then
  resolves `currentAudio` against anything already playing.
- **library-list:** `CPListTemplate` of `CPListItem`s — title, plus artist or album as detail text,
  artwork or a `book.closed` fallback, and `playbackProgress` from the saved `currentTime`. Empty
  library: *"No audiobooks yet"* with a subtitle saying books are added on the phone.
- **library-refresh (#95, #150):** every library snapshot write (`.libraryDidChange`) re-reads the
  store. Only when a row's title, detail text, cover or the order changed is the list rebuilt
  (`updateSections`); otherwise the rows stay and only their saved progress is updated in place
  (`RowContent` is the diff). So the player's bookmark refresh in `Player.play` no longer redraws the
  list.
- **saved-progress (#150):** every position save (`.playbackPositionDidSave`, posted by
  `SavePlaybackPositionUseCase`: every 10 s while playing, on pause, a book switch, a chapter jump,
  backgrounding) re-reads that one book and sets its row's progress, unless it is the playing row
  (the player drives that one). The stored copy is updated either way, so a row handed back when
  another book starts shows where its book was left.
- **rate-button (#150):** the Now Playing template has a `CPNowPlayingPlaybackRateButton`. CarPlay
  shows the rate from Now Playing info (the book's speed, see [now-playing](now-playing.md)); each
  tap moves the loaded book to the next preset (0.8, 1, 1.2, 1.5, 1.75, 2, 2.5, then back to 0.8;
  a speed between presets goes to the next one up), saved as that book's speed through
  `Player.setPlaybackRate`, the same path as the speed sheet and the lock screen. Nothing loaded:
  no-op.
- **language (#152):** CarPlay's own strings (library title, empty state, *Chapter selection*) come
  from `Localizable`, so they follow the **in-app** language, applied at launch before the scene
  connects. A change on the phone while connected (`.appLanguageDidChange`) updates the empty state
  and Up Next title in place; the library title (read-only on `CPListTemplate`) is replaced with a
  new root template when the library is on top (`templateDidAppear`), never while Now Playing or the
  chapter list is shown. Book titles, authors and chapter titles are data, not localized; chapter
  start times are `hh:mm:ss`.
- **selection:** the row handler re-fetches the model from Core Data (to pick up the latest saved
  position), plays it, and pushes the now-playing template.
- **chapter-list:** reachable from the now-playing template's Up Next **or** album-artist button.
  Marks the current chapter with `speaker.wave.2.fill`, others with `book.pages`. Tapping seeks and
  pops back.
- **live-progress:** the time subscription writes progress into `currentPlayingItem`, the row for the
  book now playing (re-resolved by URL when playback moves to another book). The URL is the book's
  identity on both sides (`player.url` and the row's book), so a book whose file moved is still
  marked playing (#186, `MovedBookIdentityTests.test_carPlay_marksTheMovedBookPlaying`).
- **siri-freshness (#160):** `didConnect` and `sceneDidBecomeActive` call `carPlayBecameActive()`,
  which asks the shared `SiriContextRefresher` (from `DependencyContainer`) for a throttled refresh,
  reason `carPlay`; see [siri-library-publish](siri-library-publish.md).
- **disconnect:** removes the now-playing observer, cancels the time **and** URL subscriptions and
  the library, position-save and language subscriptions, and nils the cached state, including the
  row map.

## How to get to it (user POV)

Connect the iPhone to a CarPlay head unit, open Abbay from the CarPlay home screen, pick a book.

## Driving it with abbay-ctl

**`verified-unreachable`.** There is no first-party UI automation for `CPTemplate` surfaces, and
Appium's XCUITest driver has a long-standing unresolved problem tapping CarPlay elements. The
options are a real head unit, or Apple's **CarPlay Simulator** — a separate Mac app shipped in
"Additional Tools for Xcode" that cables to a physical iPhone. The iOS Simulator cannot do it.

What *is* assertable without a car:

```bash
$B appgroup get abbay.diagnostics.v1          # intents fired while connected
$B appgroup get abbay.lastPlayedAudioURL      # CarPlay selection persists through Player.play
```

Everything else here should be covered by unit tests over the template-building logic once #96
gives the delegate an injection seam. Keeping template construction out of the CarPlay UI is the
standard advice for exactly this reason.

## Gotchas

Status of the seven issues this map used to list as open (from `git log` on `CarPlaySceneDelegate`
and `NowPlayingManager`; each fix is unit-tested, none was driven on a head unit):

- **#90 — Siri intents do not work in CarPlay at all.** Observed in real usage, root cause not yet
  identified, deferred and untracked. Start with `SiriDiagnostics` to establish whether intents fire.
- **#91 — fixed in #99.** Externally started playback now pushes the now-playing template
  (`showNowPlayingIfNeeded`, skipped when it is already in the stack).
- **#92, #94 — fixed in #108.** Progress is tracked by playing URL (`trackRow`, `listItemsByURL`) and
  `didDisconnect` cancels both the time and the URL subscriptions.
- **#93 — fixed in #98.** See [now-playing](now-playing.md).
- **#95 — fixed.** The list refreshes on library changes and has an empty state; a tapped row whose
  book was deleted refreshes the list instead of playing a dead URL.
- **#96 — fixed in #107.** The delegate has an injection seam and tests
  (`CarPlaySceneDelegateTests`, `CarPlayLibraryRefreshTests`, `CarPlayRateAndLanguageTests`).
- **#150 — refresh, progress and rate button**: unit-tested only. Not yet run on the CarPlay
  Simulator or a head unit (tracked on #90's device-check list); in particular whether the rate
  button's label follows a speed changed on the phone is the system's job, from Now Playing info.

**LibriVox books in CarPlay are assumed, not verified.** The delegate is unchanged on this branch. A
LibriVox book is an ordinary `AudioModel` (URL `librivox://book/<id>`, book-wide `duration`,
`currentTime` and chapters), so it lists with its cover, shows progress from `currentTime / duration`,
plays through `Player.play`, and its chapter list seeks by `startTime` in book time. No test builds
the CarPlay templates from a LibriVox model.

Other notes:

- `CPNowPlayingTemplate` reads the *same* `MPNowPlayingInfoCenter` data and remote-command handlers
  as the lock screen, so [now-playing](now-playing.md) fixes land here for free.
- `currentAudio` gates both chapter-list entry points, so when it is stale or nil the Up Next and
  album-artist buttons silently do nothing.
- Resolving `currentAudio` at connect works only because `buildLibraryTemplate()` populates
  `audioItems` first, on the preceding line. The ordering is load-bearing and undocumented in code.
