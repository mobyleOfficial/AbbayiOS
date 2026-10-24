# Siri app selection: "on Abbay", and why it depends on how recently the app ran

**Date:** 2026-10-23
**Branch:** `fix/siri-on-abbay`
**Device:** iPhone 15, iOS 26.6
**Companions:** `2026-09-12-siri-routing-diagnosis.md`, `2026-05-17-sirikit-media-providers.md`

---

## The report

"Hey Siri, play \<book\> on Abbay" was playing in YouTube Music, the default audio app, instead of Abbay.

## What we found

1. **No phrase said "on Abbay".** Every App Shortcut phrase in `AbbayAppShortcuts` said "in Abbay". `Metadata.appintents/extract.actionsdata` in the built app had not even a "Play on Abbay". So "play X on Abbay" matched nothing of ours. Siri treated it as a generic media request, which goes to the default app.
   - **Fix (this branch):** an "on" twin for every "in" phrase, plus "Play Abbay" and "Play \<book\> using Abbay".
   - **Pinned by** `AppShortcutPhraseTests`. It reads the shipped metadata and keeps the total under Apple's 1,000-phrase cap: entity phrases × 40 books / 50 chapters, 719 now.
2. **Siri cuts the request off after a title it recognizes.** On the device with the fix, the transcript read *"play Harry Potter and the Goblet of Fire (Full-Cast Edition)"*. Siri completed the library title from Abbay's own vocabulary, including the parenthetical, and ended the utterance there, so "on Abbay" never arrived.
   - With the fix, the result is **better but not complete**: instead of silently playing in YouTube Music, Siri asks *"Which app do you want to listen to this on?"* and lists Abbay first.
   - The September notes describe the same cut-off. That's why app-name-first phrases exist ("Hey Siri, Abbay play \<book\>"); they're unaffected.
3. **It works well right after the app has been opened.** In September, plain "play \<book\>" with no app name went straight to Abbay. Now it prompts, unless Abbay was opened recently. Siri's media-app ranking appears to weigh how fresh the app's signals are, and those signals decay. The owner suspects an iOS update changed the weighting; we can't confirm that.

## What Abbay tells Siri today, and when

| Signal | When it's refreshed |
| --- | --- |
| `INMediaUserContext.becomeCurrent()` (library size), Spotlight items (`LibrarySpotlightIndexer`), `INVocabulary` titles, `AbbayAppShortcuts.updateAppShortcutParameters()`, all via `SiriLibraryPublisher.publish` | Cold launch (`AbbayApp.swift`, `didFinishLaunching`) and every library change (`LibrarySnapshotWriter`) |
| `INPlayMediaIntent` interaction donation (`IntentDonor.donatePlayMedia`) | When playback starts (`Player.play`) |

Returning to the app from the background, without a cold launch, refreshes nothing. Neither does pausing or finishing a chapter.

## The plan (not built yet)

Siri's ranking is opaque. Apple documents the inputs, not their weights. So this is an experiment, to be judged on the device, not by tests.

1. **Refresh on foreground and on pause.** Call `SiriLibraryPublisher.publish(audios:)` when the scene becomes active (`scenePhase == .active`) and when playback pauses or stops, not only at a cold launch. Throttle it, e.g. at most once every 10 minutes, so a busy session doesn't spam the system. Cheap and low-risk, but it only helps when the app is used.
2. **Background refresh.** Register a `BGAppRefreshTask` (`BGTaskSchedulerPermittedIdentifiers` in `Info.plist`, background mode `fetch`), scheduled about daily, that re-runs the same publish. It aims at the actual complaint, a stale context when the app hasn't been opened for a while, but the effect on Siri is unproven. iOS decides when, or whether, it runs, based on usage.
3. **More recency donations.** Donate an `INPlayMediaIntent` interaction, with the book as an `INMediaItem`, on pause and at chapter boundaries as well as at play start, so the system sees ongoing listening, not just a start.

**Constraints:**
- Keep the deployment target at iOS 17.
- No new permissions beyond background fetch.
- The privacy story is unchanged: these are on-device donations to the system, and nothing leaves the device.

**How to judge it:**
1. Install the experiment build over the tailnet page.
2. Over a day or two, after the app has been closed for several hours, say plain "Hey Siri, play \<book\>" and "Hey Siri, play \<book\> on Abbay".
3. Count how often it goes straight to Abbay, versus the app prompt, versus another app.
4. Compare against this branch's build.

If there's no improvement, drop 2 (it costs battery and review surface) and keep 1 and 3 only if they show a difference.

**Debugging aid:** `SiriDiagnostics` (see the September notes) records which Abbay path served a request. It can't explain the prompt itself, because Abbay isn't reached until the user picks it. Pulling it needs the phone on USB or the same Wi-Fi as the Mac (`xcrun devicectl … --domain-type appGroupDataContainer`).

## Not part of this plan: iOS 27

Xcode 27 adds the App Intents `.audio` domain (`playAudio`, `audiobook`). Adopting it does **not** mean raising the minimum iOS: build with the iOS 27 SDK, mark the new intents `@available(iOS 27, *)`, and keep SiriKit plus App Shortcuts for iOS 17–26. It wouldn't help iOS 26 devices like the test iPhone, so it belongs on the separate Xcode 27 branch.
