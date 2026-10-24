# CarPlay

`CarPlaySceneDelegate` — the library list, the now-playing template and the chapter list on a car
head unit. The entitlement is approved and this surface **ships**, but nothing automated reaches it and
two of its original bugs (#90, #95) are still open.

## Sub-features

- **connect:** `didConnect` stores the interface controller, configures
  `CPNowPlayingTemplate.shared` (Up Next button enabled, titled *"Chapter selection"*, self
  registered as observer), installs player observers, sets the library as root, then resolves
  `currentAudio` against anything already playing.
- **library-list:** `CPListTemplate` of `CPListItem`s — title, plus artist or album as detail text,
  artwork or a `book.closed` fallback, and `playbackProgress` from the saved `currentTime`.
- **selection:** the row handler re-fetches the model from Core Data (to pick up the latest saved
  position), plays it, and pushes the now-playing template.
- **chapter-list:** reachable from the now-playing template's Up Next **or** album-artist button.
  Marks the current chapter with `speaker.wave.2.fill`, others with `book.pages`. Tapping seeks and
  pops back.
- **live-progress:** the time subscription writes progress into `currentPlayingItem`, the row for the
  book now playing (re-resolved by URL when playback moves to another book).
- **siri-freshness (#160):** `didConnect` and `sceneDidBecomeActive` call `carPlayBecameActive()`,
  which asks the shared `SiriContextRefresher` (from `DependencyContainer`) for a throttled refresh,
  reason `carPlay`; see [siri-library-publish](siri-library-publish.md).
- **disconnect:** removes the now-playing observer, cancels the time **and** URL subscriptions, and
  nils the cached state, including the row map.

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
- **#95 — still open.** The list is built once at connect (`buildLibraryTemplate`), with no refresh
  when the library changes and no empty state. Relevant to LibriVox: a book downloaded from the phone
  while CarPlay is connected does not appear until reconnect, and a deleted one still taps through to
  a dead URL via the `?? audio` fallback.
- **#96 — fixed in #107.** The delegate has an injection seam and tests.

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
