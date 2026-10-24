# Abbay feature map

Behaviour-level inventory of what a user can do in Abbay. Agents use it to decide what to drive
and what evidence counts; humans use it as the regression checklist.

## Status: identifiers landed and verified; `abbay-ctl` not built yet

There is no `abbay-ctl` and no `SKILL.md` in this directory yet, so each file's *Driving it with
abbay-ctl* section is still a **specification** — the commands we want, not commands that exist.
Treat a command there as a requirement.

Accessibility identifiers, however, are now implemented and **proven by
`AbbayUITests/AccessibilityIdentifierTests`**. Each feature file marks its identifiers as
`verified` or `not implemented` so a driver author knows what is actually addressable.

### The rule that matters: identifiers go on leaves, never on containers

SwiftUI applies `.accessibilityIdentifier` to **every** accessibility element in the subtree, so
an identifier on a container silently overwrites its children's. The first attempt at this pass
put identifiers on containers and destroyed 18 of 21 child identifiers without any build or test
failure — the accessibility tree simply showed the container's id repeated on every descendant:

```
Image,      identifier: 'library.row.0', label: 'Photo'
StaticText, identifier: 'library.row.0', label: 'Seeded Plain Book'
Button,     identifier: 'library.row.0'
```

Consequences baked into the current design:

- There is **no `library.root` and no `player.root`** — both clobbered everything beneath them.
  Use `library.list` / `library.empty` and a specific player control as the "screen is up" signal.
- `library.row.<n>` is **not** addressable on its own. Address a row through one of its leaves
  (`library.row.<n>.title` is the usual handle, and tapping it opens the details screen).
- The mini player's id (`miniPlayer.bar`) is on its title/subtitle element, not the bar container,
  so `miniPlayer.playPause` and `miniPlayer.progress` stay addressable beside it.

Convention remains `<screen>.<element>[.<qualifier>]`. Constants live in
`Abbay/Core/AccessibilityID.swift`, compiled into both the app and the UI test target because a
UI test bundle runs out of process and cannot `import Abbay`.

### Row order is not insertion order

`LoadAllAudiosUseCase` applies no sort, so positional indices do not match the order books were
added. Resolve a row by matching its title label rather than assuming an index.

## Baseline preconditions

- Fresh build: the app binary is newer than every source file under `Abbay/`.
- Portrait iPhone only (`TARGET_DEVICE_FAMILY: 1`), forced dark mode
  (`MediaListView` sets `.preferredColorScheme(.dark)`), deployment target iOS 17.0.
- The library is seeded through launch arguments, handled by `UITestSeeder` in DEBUG builds and
  named in `Abbay/Core/LaunchArgument.swift`. The seeder and the other UI-test stand-ins live in
  `Abbay/DebugSupport/`, which `DebugOverrides` reads and Release builds leave out:
  - `-seedLibrary` — replaces the library with two deterministic books, one chaptered (three
    chapters) and one without chapters.
  - `-resetLibrary` — empties the library, for the empty state.
  - `-seedFillerBooks` — with `-seedLibrary`, also adds filler books so the list is longer than
    the screen (the mini player's last-row inset test).
  - `-stubLibriVox` — answers LibriVox requests from memory (`UITestLibriVoxClient`: Popular is the
    one stub book, which any query containing "stub" also finds) and swaps in a download manager
    that downloads nothing and never reports state (`UITestDownloadManager`), plus a 50 ms search
    debounce. Combine it with the others; without it search and downloads use the real network.

  `-seedLibrary`/`-resetLibrary` clear first, so repeated runs are deterministic rather than
  cumulative. All of them are DEBUG-only: the `UITest*` files are excluded from Release and
  `DebugOverrides` returns `nil` there. The seeded models carry **no playable audio**: pressing a
  seeded row's play button loads the book (the mini player and the row's loaded state appear), but
  nothing plays and the clock doesn't move, so anything needing real playback — time advancing,
  tapping a chapter — is unreachable this way. The stub LibriVox book is the same: Play opens the
  details screen and the mini player appears; its chapter URL is `/dev/null`.

  Not reachable by any launch configuration: real search results, real downloads and their
  progress/ring/statuses (the stub manager's state stream is empty), the cellular alert (the stub
  book is 1,000 bytes), and multi-file playback. Those are covered by unit tests only — see
  [downloads](downloads.md).
- A real chaptered audiobook fixture is committed at `AbbayTests/Fixtures/Christmastide.m4b`
  (public domain; see its README). It is a resource of the **unit** test bundle, so `FileLoader`
  and the bookmark layer are tested against a real asset. It is not in the app bundle, which is
  why the UI seed path uses synthetic models instead.
- UI tests run from their own scheme via `bundle exec fastlane ui_test_project`, kept out of
  `test_project` so the unit suite stays fast. `run_ui_tests` in `.actions.yml` gates CI.
  `bundle exec fastlane verify` runs lint, unit and UI suites on the `.actions.yml` device
  (iOS 26.4). The tab bar and mini player have two code paths (system accessory on 26.1+,
  hand-built dock below), so also run the UI scheme once on an iOS 18.5 simulator
  (`xcodebuild test -scheme AbbayUITests -destination 'platform=iOS Simulator,name=…,OS=18.5'`).
- Out-of-band state lives in the App Group `group.com.edyuto.abbay`, readable with
  `xcrun simctl get_app_container booted com.edyuto.Abbay group`. Assert side effects there
  (`abbay.lastPlayedAudioURL`, `abbay.librarySnapshot.v1`, `abbay.diagnostics.v1`,
  `abbay.audioSessionUnavailable`) rather than trusting pixels.

## Proof and skip reporting

The feature file defines the coverage set. Exercise every reachable entry point and the success,
cancel, error, empty and persistence paths a change can affect. Record the action and the final
state. When a path is unreachable, name the blocker and cover the closest real path.

Three surfaces are **`verified-unreachable` by construction** — document them, do not pretend to
drive them:

| Surface | Blocker |
|---|---|
| Siri utterances | Cannot be invoked in the iOS Simulator. Intents are reachable in code; the *voice* path is not. |
| CarPlay | No first-party UI automation for `CPTemplate`. Needs a head unit or Apple's CarPlay Simulator (Additional Tools for Xcode, cables to a physical iPhone). |
| Lock screen / Control Center | System UI outside the app's process. |

For these, `SiriDiagnostics` (App Group key `abbay.diagnostics.v1`, last 25 events) is the
substitute: it records every intent firing across processes and survives app death.

## Full sweep (top to bottom)

### Shell and library

- [app-shell](app-shell.md): launch ordering, audio-session activation, scene routing, the root and its one playback source, Siri authorisation.
- [tabs](tabs.md): the Library and Search tabs, both searches, the system vs hand-built tab bar, the keyboard.
- [library](library.md): the audiobook list, empty state, delete, toolbar, local-only search.
- [import](import.md): the document picker, metadata and chapter extraction, security-scoped bookmarks.
- [media-row](media-row.md): the per-book row component, including the download ring.

### LibriVox

- [librivox-details](librivox-details.md): the details page in the Search tab — Download, cellular warning, Play, chapter list.
- [downloads](downloads.md): background chapter-by-chapter downloads, streaming, pause/resume, restore, delete.

### Playback

- [mini-player](mini-player.md): the one-row bar above the tabs, its tap, drag and swipes, and the expansion into the details screen.
- [player](player.md): the details screen (no longer a sheet), its grabber and close, scrubbing, chapter list.
- [now-playing](now-playing.md): lock screen, Control Center and remote commands.

### Siri and system integration

- [siri-app-intents](siri-app-intents.md): the seven App Intents and their spoken phrases.
- [siri-playmedia](siri-playmedia.md): `INPlayMediaIntent` across the extension and the in-app handler.
- [siri-library-publish](siri-library-publish.md): vocabulary, entity queries, Spotlight, media affinity.

### CarPlay

- [carplay](carplay.md): library list, now-playing template, chapter list — #90 and #95 still open; the other five fixed (#98-#108).
