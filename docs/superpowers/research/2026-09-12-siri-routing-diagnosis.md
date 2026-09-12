# Siri routing diagnosis — why most commands failed

**Date:** 2026-09-12
**Branch:** `feat/siri-phase2-impl` (PR #80)
**Companions:** `2026-05-17-phase-1-limitations.md`, `2026-05-17-sirikit-media-providers.md`

---

## Evidence gathered before changing anything

Pulled from the paired iPhone (iOS 26.6, iPhone 15 Plus) and from the build:

| Check | Result |
| --- | --- |
| App Group container on device | Snapshot present: 2 books, both with bookmark data |
| `abbay.lastPlayedAudioURL` on device | Set, points at a real file |
| `abbay.audioSessionUnavailable` on device | Absent — the unavailable flag was **not** stuck |
| Extension embedded in the app bundle | Yes, `PlugIns/AbbayIntents.appex` |
| Signed entitlements | App: Siri + App Group. Extension: App Group |
| Device provisioning | Device build signs and installs with no profile errors |
| AppIntents metadata | 5 phase-1 intents registered, 0 assistant schemas |

So the cross-process plumbing built in phase 2 was working. The failure was
upstream of it: Siri was never handing the request to the extension.

## Root causes

1. **No media category declared.** Apple requires a media app to opt in to Siri
   media control by declaring at least one supported category. The extension
   declared `INPlayMediaIntent` but no `SupportedMediaCategories`, and the app
   declared neither `INIntentsSupported` nor `INSupportedMediaCategories`. Siri
   resolved the app by name, found no media capability, and answered "Abbay
   hasn't added support for that with Siri".

2. **Siri authorization was never requested.** SiriKit does not dispatch to an
   Intents extension until the user grants Siri access. AppIntents need no such
   grant — which is exactly why the phase-1 commands worked and everything on
   the media path did not.

3. **Title-less requests matched nothing.** "Play in Abbay" arrives with an
   empty media name, and so does "play X **on** Abbay" (the "on" and "using"
   prepositions are reported to deliver an empty media search). The fuzzy
   matcher returns no candidates for empty input, so every one of those became a
   no-match.

4. **The last-played pointer was read from the wrong place** in the extension
   handler — the App Group suite directly rather than `LastPlayedStore`, which
   skips the phase-1 fallback.

5. **The audio-unavailable gate could stick.** It trusted a flag from a previous
   launch with no retry. (Partly addressed in the working tree already; it had
   no test seam, and four tests were failing because of it.)

6. **Nothing taught Siri the library.** No `INVocabulary` titles, no
   `INMediaUserContext`, and no `updateAppShortcutParameters()` call — Apple is
   explicit that entity-parameter phrases do not resolve until the system has
   fetched entities at least once.

## What changed

- Both Info.plists declare audiobook + general media categories; the app adds
  `INIntentsSupported`, `NSUserActivityTypes`, `NSAppleMusicUsageDescription`,
  and `INAlternativeAppNames` synonyms for the "a bay" mis-transcription.
- Siri authorization is requested at launch.
- Title-less play resumes the last-played book, else the first in the library.
- `SiriLibraryPublisher` keeps `INVocabulary`, AppShortcuts entity parameters
  and `INMediaUserContext` in step with the library on every mutation and at
  launch.
- New `AudiobookEntity` / `ChapterEntity` parameters give one-utterance phrases:
  "Play <title> in Abbay" and "Play chapter N in Abbay". This removes phase-1
  limitations 3, 5 and 9 — the `String`-parameter restriction that forced a
  second "Which audiobook?" turn does not apply to `AppEntity` parameters.

## Device verification

Preconditions: unlock the phone, open Abbay once (the install is already on the
device), accept the Siri permission prompt, tap a book once, then wait about a
minute for indexing.

| Say | Expect | Path |
| --- | --- | --- |
| "Hey Siri, open Abbay" | App opens | System app launch |
| "Hey Siri, play in Abbay" | Resumes last book | AppShortcuts |
| "Hey Siri, play Harry Potter and the Goblet of Fire in Abbay" | Plays it, one utterance | AppShortcuts entity phrase |
| "Hey Siri, open Harry Potter and the Goblet of Fire in Abbay" | Same | AppShortcuts entity phrase |
| "Hey Siri, play chapter 4 in Abbay" | Jumps to chapter 4 | AppShortcuts entity phrase |
| "Hey Siri, next chapter in Abbay" | Skips | AppShortcuts |
| "Hey Siri, pause Abbay" | Pauses | AppShortcuts |
| "Hey Siri, pause" (while playing) | Pauses | MPRemoteCommandCenter |
| "Hey Siri, play Goblet of Fire from Abbay" | Plays it | SiriKit media extension |
| "Hey Siri, play Goblet of Fire" (no app name) | May go elsewhere at first | Siri app-selection learning |

If a media-path phrase still fails, check in this order: Settings → Apps → Abbay
→ Siri toggle is on; then Console with subsystem `com.edyuto.Abbay.AbbayIntents`
to see whether `decide entered` is logged at all. No log line means Siri never
reached the extension (a registration problem); a log line with an outcome means
the request arrived and the decision is ours.

## Known remaining limits

- **App-name-less "play <title>"** is not something an app can claim. Siri
  learns it from donations, `INMediaUserContext` and usage. There is no
  user-facing default-media-app setting.
- **Phrase budget.** Apple allows an app 1,000 trigger phrases counting every
  parameter permutation, so entity suggestions are capped (40 books, 50
  chapters). Books past the cap still resolve through free-form matching, they
  just have no pre-expanded phrase.
- **The iOS 27 path exists but is out of reach here.** Apple's App Intents
  `.audio` domain (`playAudio`, `audiobook`) is iOS 27 / Xcode 27 only. There is
  no media domain in the iOS 26 SDK's assistant schemas, and the `.books`
  schemas are Shortcuts-only and already deprecated in favour of `.audio`. So
  SiriKit `INPlayMediaIntent` remains correct for an iOS 17 deployment target;
  revisit when the toolchain moves to Xcode 27.
