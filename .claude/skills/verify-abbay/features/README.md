# Abbay feature map

Behaviour-level inventory of what a user can do in Abbay. Agents use it to decide what to drive
and what evidence counts; humans use it as the regression checklist.

## Status: identifiers landed and verified; `abbay-ctl` not built yet

There is no `abbay-ctl` and no `SKILL.md` in this directory yet, so each file's *Driving it with
abbay-ctl* section is still a **specification** — the commands we want, not commands that exist.
Treat a command there as a requirement.

Every id in those commands is an `AccessibilityID` constant, and every single-dash argument to
`$B launch` (`-seedLibrary`, `-stubLibriVox`, ...) is a `LaunchArgument` name passed through to the
app verbatim, so the spec has no second set of names to drift. Double-dash options (`--reset`,
`--clear`) belong to `abbay-ctl` itself. Elements without an id are addressed by what XCUITest
uses instead (`placeholder:"…"` for a search field).

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
  (`AppRootView` sets `.preferredColorScheme(.dark)`), deployment target iOS 17.0.
- The library is seeded through launch arguments, handled by `UITestSeeder` in DEBUG builds and
  named in `Abbay/Core/LaunchArgument.swift`. The seeder and the other UI-test stand-ins live in
  `Abbay/DebugSupport/`, which `DebugOverrides` reads and Release builds leave out:
  - `-seedLibrary` — replaces the library with two deterministic books, one chaptered (three
    chapters) and one without chapters. They play real audio (#147): each is a hard link, under
    its own name in Application Support/`UITestSeedAudio`, to the Debug-only
    `Christmastide.m4b` fixture (rows are keyed by URL, so each book needs its own file).
  - `-resetLibrary` — empties the library, for the empty state.
  - `-seedFillerBooks` — with `-seedLibrary`, also adds filler books so the list is longer than
    the screen (the mini player's last-row inset test).
  - `-seedLongBook` — with `-seedLibrary`, also adds *Seeded Long Book*, 60 one-minute chapters,
    so the details screen's chapter list is far longer than the screen (the list-at-top collapse
    tests).
  - `-seedPlayableBook` — with `-seedLibrary`, also adds *Seeded Playable Book*: the real
    four-chapter LibriVox m4b from `AbbayTests/Fixtures/Christmastide.m4b`, copied into Debug
    builds only, saved 200 s in (chapter 2, 39% through it). The one seeded book whose chapters
    and duration are the file's own, for the mini player's *Next chapter* / *Restart chapter*
    tests. It makes sound: pause it.
  - `-seedMissingFile` — with `-seedLibrary`, also adds *Seeded Missing Book*, whose file doesn't
    exist: what a moved or renamed import looks like. Play shows the moved-file banner (#139's
    `NoticeUITests`). Its duration is the fixture's (831.6 s), so `-stubMovedImport`'s file is
    recognisably its own.
  - `-seedTimeLeftEdges` — with `-seedLibrary`, also adds *Seeded Finished Book* (no chapters,
    saved at its end: the row reads "0s left") and *Seeded Hour Book* (a first chapter of exactly
    one hour: once loaded, the mini player reads "Chapter 1 · 1 hr left"), the time-left edge cases
    of #152. No audio (unlike the other seeds), so their clocks stay put: loading the hour book
    also shows the "moved or renamed" notice.
  - `-forceReduceMotion` — run with Reduce Motion on whatever the system setting says
    (`DebugOverrides.reduceMotion`, read by the `@ReduceMotion` property wrapper every view uses
    instead of `\.accessibilityReduceMotion`), because XCUITest can't switch the setting. It
    reaches every surface on iOS 17, 18 and 26: an environment override at the root didn't cross
    a pushed page on iOS 18 (#185). SwiftLint's `reduce_motion_through_wrapper` rule keeps views
    off the raw environment value.
  - `-stubLibriVox` — answers LibriVox requests from memory (`UITestLibriVoxClient`: Popular is the
    one stub book, which any query containing "stub" also finds; its size is 29,670,000 bytes, so
    it shows a decimal separator) and swaps in a download manager
    that downloads nothing and, without `-stubDownloadStates`, never reports state
    (`UITestDownloadManager`), plus a 50 ms search
    debounce. Combine it with the others; without it search and downloads use the real network.
    The stub book's cover is a `/dev/null` file URL, which the cover host allowlist refuses, so it
    shows `cover.failed`.
  - `-stubCovers` — with `-stubLibriVox`, the stub book's cover is an archive.org URL that
    `UITestCoverNetwork` answers after 12 s with a generated image, so `cover.loading` and
    `cover.loaded` can be seen. Covers use their own disk cache (`Caches/UITestCovers`), emptied at
    launch (see [librivox-details](librivox-details.md) *cover-loading*).
  - `-stubCoversOffline` — with `-stubCovers`, every cover request fails and that disk cache is
    kept, so a cover can only come from what an earlier `-stubCovers` launch stored.
  - `-stubDownloadStates` — with `-stubLibriVox`, the stub book is 120 MB in three chapters (so on a
    metered path Download asks), and the stub download manager publishes a fixed state for every
    book it is given: chapter 0 downloaded, 1 waiting, 2 failed; pause, resume and retry change it
    (see [downloads](downloads.md)).
  - `-stubPathCellular`, `-stubPathHotspot`, `-stubPathLowDataMode` — the download screens read a
    fixed network path (`NetworkPathMonitor.app`): cellular, a Personal Hotspot or Low Data Mode
    Wi-Fi, all online and metered. The player and the real download manager keep the real path.
  - `-stubFailingImport` — *Import file* skips the system picker and imports two files that don't
    exist, so the failed-import banner shows (see [notices](notices.md)).
  - `-stubMovedImport` — *Import file* skips the system picker and imports *Seeded Missing Book*'s
    file from where it moved to (`UITestSeedAudio/moved/missing.m4b`, a copy of the fixture). With
    `-seedMissingFile` the book is relinked, not added, and plays (#196, see [import](import.md)).
  - `-resetSettings` — start from default settings kept in memory for that launch only, so a test
    that changes the language, a skip amount or a speed leaves nothing behind (see [settings](settings.md)).

  `-seedLibrary`/`-resetLibrary` clear first, so repeated runs are deterministic rather than
  cumulative (a book whose file moved included, #176). A launch with any of these arguments
  (`LaunchArgument.all`) doesn't ask for Siri authorization, so a fresh simulator shows no
  *"Would you like to use Abbay with Siri?"* alert to race the first tap (#163); launch without
  arguments to see it. All of them are DEBUG-only: the `UITest*` files are excluded from Release and
  `DebugOverrides` returns `nil` there, and Release excludes the fixture too
  (`EXCLUDED_SOURCE_FILE_NAMES`). The seeded books **play** (#147): pressing a seeded row's play
  button plays the fixture's audio, and the clock moves. Their titles, durations and chapters are
  the seed's own, not the file's (14 min long): *Seeded Long Book*'s chapters past the 13th start
  past the end of the audio. It makes sound: pause it. Only *Seeded Missing Book*
  (`-seedMissingFile`) has no file, and Play on it shows the moved-file banner (`notice.banner`,
  about 5 s, doesn't take touches). The stub LibriVox book still has no audio: Play opens the
  details screen and the mini player appears, its chapter URL is `/dev/null`, and the banner says
  *Couldn't play this chapter*.

  Not reachable by any launch configuration: real search results, real downloads (their
  progress, ring, statuses and the cellular alert are reachable with the stub's fixed states, see
  `-stubDownloadStates`), and multi-file playback. Those are covered by unit tests only — see
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
- [notices](notices.md): the app-wide error banner, and every failure that reports to it.
- [settings](settings.md): the gear's sheet — default speed, skip amounts, cellular downloads, space used, delete finished, language, About.

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
