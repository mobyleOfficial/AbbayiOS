# CarPlay

`CarPlaySceneDelegate` — the library list, the now-playing template and the chapter list on a car
head unit. The entitlement is approved and this surface **ships**, but it carries six open bugs and
nothing automated reaches it.

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
- **live-progress:** the time subscription writes progress into `currentPlayingItem`.
- **disconnect:** removes the now-playing observer, cancels the *time* subscription, and nils the
  cached state.

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

This surface has the highest known-defect density in the app. All six are filed:

- **#90 — Siri intents do not work in CarPlay at all.** Observed in real usage, root cause not yet
  identified. Start with `SiriDiagnostics` to establish whether intents fire.
- **#91 — the now-playing template is never pushed for externally started playback.**
  `handleAudioSelection` pushes it; the URL subscription only assigns `currentAudio`. Audio plays
  while CarPlay sits on the library list, which is indistinguishable from "Siri did nothing" and is
  probably a large part of #90.
- **#92 — the progress bar tracks the wrong row.** Progress is computed from `currentAudio` but
  written to `currentPlayingItem`, and those two are updated by different paths. Switch books from
  the phone and the old row animates with the new book's position, at the wrong ratio.
- **#93 — the Siri playback gate can report stale state.** Not CarPlay-specific, but it surfaces
  here. See [now-playing](now-playing.md).
- **#94 — the URL subscription is neither idempotent nor cancellable.** `setupObservers()` runs on
  every `didConnect`; `subscribeToPlayUrlPublisher` has no guard and `didDisconnect` can only cancel
  the time subscription.
- **#95 — the list is built once at connect.** No refresh when the library changes, and no empty
  state at all. A row for a deleted book taps through to a dead URL via the `?? audio` fallback.
- **#96 — no injection seam, no tests.** Use cases are constructed directly instead of resolved from
  `DependencyContainer`, so none of the above is unit-testable today.

Other notes:

- `CPNowPlayingTemplate` reads the *same* `MPNowPlayingInfoCenter` data and remote-command handlers
  as the lock screen, so [now-playing](now-playing.md) fixes land here for free.
- `currentAudio` gates both chapter-list entry points, so when it is stale or nil the Up Next and
  album-artist buttons silently do nothing.
- Resolving `currentAudio` at connect works only because `buildLibraryTemplate()` populates
  `audioItems` first, on the preceding line. The ordering is load-bearing and undocumented in code.
