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

## Two further root causes found during device testing

7. **Speech-to-text heard "A Bay".** With the app name missing from the
   transcript, no AppShortcut phrase could match and the whole utterance fell
   through to the media domain. Fixed by declaring `CFBundleDisplayName`,
   `CFBundleSpokenName` and `INAlternativeAppNames` synonyms, and by adding
   app-name-first phrase variants so a truncated tail costs nothing.

8. **The in-app dispatch path was unserved.** Declaring `INIntentsSupported`
   made iOS dispatch `INPlayMediaIntent` to the app instead of the extension.
   The app offered only `application(_:handle:)`, so nothing resolved the media
   items and the router returned a failure. Once resolution was added, playback
   started but Siri still spoke a generic error, because a bare completion gives
   the system no resolve or confirm phase. `InAppPlayMediaHandler`, returned from
   `application(_:handlerFor:)`, serves the full lifecycle and settled it.

## Outcome

Confirmed working on device (iPhone 15 Plus, iOS 26.6):

| Say | Result |
| --- | --- |
| "Hey Siri, play harry potter and the goblet of fire" | Plays in Abbay, **no app name needed** |
| "Hey Siri, play harry potter and the goblet of fire in abbay" | Plays in Abbay |
| "Hey Siri, play chapter 4 in Abbay" | Jumps to chapter 4 |
| "Hey Siri, play in Abbay" | Resumes the last book |
| "Hey Siri, next chapter in Abbay" / "pause" | Skips / pauses |

The app-name-less case is worth calling out: Siri's media app selection now picks
Abbay on its own. That is the behaviour the phase-1 notes recorded as
unreachable, and it came from the media-provider registration as a whole —
categories, authorization, `INMediaUserContext`, `INVocabulary`, Spotlight
indexing and playback donations together.

## How to debug this again

`SiriDiagnostics` writes a ring buffer into the App Group. Read it without root
or a debugger attached:

```
xcrun devicectl device copy from --device <id> \
  --domain-type appGroupDataContainer \
  --domain-identifier group.com.edyuto.abbay \
  --source Library/Preferences --destination ./pull
```

Then decode `abbay.diagnostics.v1` from the plist. Entries name the path that
served a request (`appintent …`, `inapp resolve/confirm/handle`, `ext …`), the
Siri authorization status at launch, and how many entities the queries returned.
Absence of an entry is itself the signal: it means Siri never reached that path.
The trail records outcome labels only, never what was said.

## Remaining limits

- **Phrase budget.** Apple allows 1,000 trigger phrases per app counting every
  parameter permutation, so entity suggestions are capped at 40 books and 50
  chapters. Titles past the cap still resolve through free-form matching.
- **The iOS 27 path.** Apple's App Intents `.audio` domain (`playAudio`,
  `audiobook`) is iOS 27 / Xcode 27 only. The iOS 26 SDK has no media domain in
  its assistant schemas, and the `.books` schemas are Shortcuts-only and already
  deprecated in favour of `.audio`. SiriKit `INPlayMediaIntent` remains correct
  for an iOS 17 deployment target; revisit when the toolchain moves to Xcode 27.
- **Diagnostics are shippable but optional.** If the trail is not wanted in
  release builds, `SiriDiagnostics.record` is the single call site to gate.
