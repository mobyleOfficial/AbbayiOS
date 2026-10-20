# Abbay feature map

Behaviour-level inventory of what a user can do in Abbay. Agents use it to decide what to drive
and what evidence counts; humans use it as the regression checklist.

## Status: specification, not yet executable

There is no `abbay-ctl` and no `SKILL.md` in this directory yet — this map is deliberately the
first thing built, because it is the only part with no dependencies. It serves two purposes:

1. **Inventory.** What surfaces exist, how a user reaches them, and where the known traps are.
2. **Specification for the harness.** Each file's *Driving it with abbay-ctl* section is written
   as the commands we *want*, not commands that exist. Taken together they define `abbay-ctl`'s
   surface before a line of it is written. Treat a command here as a requirement.

Abbay also has **no accessibility identifiers today** (`grep -c accessibilityIdentifier` → 0).
Every identifier named in this map is one that has to be *added*. The convention is
`<screen>.<element>[.<qualifier>]`, matching the shape used in sibling projects.

## Baseline preconditions

- Fresh build: the app binary is newer than every source file under `Abbay/`.
- Portrait iPhone only (`TARGET_DEVICE_FAMILY: 1`), forced dark mode
  (`MediaListView` sets `.preferredColorScheme(.dark)`), deployment target iOS 17.0.
- The library must be seeded before any playback flow. There is no backend and no fixture in the
  repo yet; the planned seam is a `-seedLibrary` launch argument plus a committed public-domain
  LibriVox audiobook with real chapter metadata. Until that exists, every playback feature is
  blocked on a manual import.
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

- [app-shell](app-shell.md): launch ordering, audio-session activation, scene routing, Siri authorisation.
- [library](library.md): the audiobook list, empty state, delete, toolbar.
- [import](import.md): the document picker, metadata and chapter extraction, security-scoped bookmarks.
- [media-row](media-row.md): the per-book row component.

### Playback

- [player](player.md): the full-screen player sheet, scrubbing, chapter list.
- [floating-player](floating-player.md): the mini player docked over the library.
- [now-playing](now-playing.md): lock screen, Control Center and remote commands.

### Siri and system integration

- [siri-app-intents](siri-app-intents.md): the seven App Intents and their spoken phrases.
- [siri-playmedia](siri-playmedia.md): `INPlayMediaIntent` across the extension and the in-app handler.
- [siri-library-publish](siri-library-publish.md): vocabulary, entity queries, Spotlight, media affinity.

### CarPlay

- [carplay](carplay.md): library list, now-playing template, chapter list — **ships with six open bugs** (#90-#96).
