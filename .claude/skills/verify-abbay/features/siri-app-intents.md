# Siri — App Intents

The seven modern `AudioPlaybackIntent`s and the spoken phrases registered for them. This is the
half of Siri that Apple's `AppIntentsTesting` framework can validate.

## Sub-features

- **ResumeAbbayIntent** — resumes `LastPlayedStore.lastPlayedURL()`. Dialogs: *"Add a book in Abbay
  first."* (no pointer), *"Cannot find that audiobook…"* (dead pointer, which it then clears),
  *"Playing \<title>."*
- **PauseAbbayIntent** — gated on `NowPlayingManager.currentAudio`. *"Nothing is playing."* /
  *"Paused."*
- **NextChapterIntent** / **PreviousChapterIntent** — same gate. *"Nothing is playing. Say 'Play in
  Abbay' to start."* / *"Next chapter."* / *"Previous chapter."*
- **PlayAudiobookIntent** — takes an `AudiobookEntity`, so the title can live inside the phrase and
  resolve in one utterance.
- **PlayBookByNameIntent** — takes a `String`, which AppIntents refuses to interpolate into a
  phrase, so it always costs a second "Which audiobook?" turn. Kept deliberately for its
  input-echoing no-match dialog: *"No audiobook matches '\<input>'."*
- **PlayChapterIntent** — takes a `ChapterEntity`. Seeks if a book is loaded; otherwise resumes the
  last-played book positioned at that chapter by setting `currentTime` before `play`.
- **phrase-registration:** `AbbayAppShortcuts` registers all seven. Entity phrases lead with the app
  name on purpose — Siri completes a known media title from registered vocabulary and then ends the
  utterance, so establishing the app first means a truncated tail costs nothing.
- **audio-session guard:** every intent begins with `AudioSessionActivator.attemptActivation()` and
  returns *"Audio temporarily unavailable. Try again in a moment."* on failure.
- **diagnostics:** every intent calls `SiriDiagnostics.record("appintent <Name> fired")` first.

## How to get to it (user POV)

Speak a phrase, or run the shortcut from the Shortcuts app / Spotlight. Phrases include *"Play in
Abbay"*, *"Pause Abbay"*, *"Next chapter in Abbay"*, *"Abbay play \<title>"*, *"Play \<chapter> in
Abbay"*.

## Driving it with abbay-ctl

The *voice* path is `verified-unreachable` — Siri cannot be invoked in the simulator. The *intent*
path is reachable two ways:

```bash
$B diagnostics --clear
# ... trigger however possible ...
$B diagnostics                                # assert "appintent <Name> fired"
$B appgroup get abbay.lastPlayedAudioURL
$B wait library.floatingPlayer                # in-app proof that playback actually started
```

The durable answer is **`AppIntentsTesting`** (Xcode 27 / iOS 27 SDK): it executes intents through
the real App Intents stack with no UI automation and no mocks, building `IntentDefinitions` from the
bundle identifier so the test never imports the app target. It needs a UI-test bundle — Abbay has
no UITests target today — and an iOS 27 simulator, while the app itself stays on iOS 17.

## Gotchas

- **Dialog strings are spec-locked and unit-tested.** They are lifted into `static let`s precisely
  so a reworded response fails a test. Fix state, not wording.
- All seven dialogs are **hardcoded English**. `Localizable.xcstrings` has six keys total and none of
  them are Siri strings — that is issue #83. Do not list extra languages on the store page.
- The Pause / Next / Previous gate used to inherit #93 (success with nothing playing); #98 resets
  the gate on cleanup — see [now-playing](now-playing.md).
- **LibriVox books are treated as one book here by assumption.** The intents are unchanged on this
  branch; next/previous/play-chapter go through `Player` and `AudioModel.chapters[].startTime`, which
  for a LibriVox book are book-time and cumulative, so a chapter jump should load that chapter's file.
  Siri cannot run in the Simulator and no unit test drives these intents with a multi-file model, so
  this is expected behaviour, not verified behaviour.
- `PlayBookByNameIntent`'s two-turn behaviour is a deliberate trade-off, not a bug. Do not "fix" it
  by swapping the parameter to an entity — that is what `PlayAudiobookIntent` already is.
- `AudiobookEntityQuery` falls back to the App Group snapshot when `DependencyContainer.isConfigured`
  is false, because entity queries can be evaluated outside the launch path.
- A stale `abbay.audioSessionUnavailable` flag makes every one of these answer "Audio temporarily
  unavailable" — check it before investigating anything else.
