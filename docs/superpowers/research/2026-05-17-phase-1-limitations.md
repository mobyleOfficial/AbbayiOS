# Phase-1 Siri Integration — Known Limitations

**Date:** 2026-05-17
**Companion to:** spec `2026-05-16-siri-design.md`, plan `2026-05-16-siri.md`, research `2026-05-17-sirikit-media-providers.md`.
**Purpose:** Single-page reference of every limitation v1 ships with. Each entry: what fails, why, workaround for users today, phase-2 fix that resolves it.

---

## 1. Cold-start "play" verb routes to the system's default media app

**What fails:** With Abbay **not running**, `"Hey Siri, play in Abbay"` and `"Hey Siri, play on Abbay"` route to YouTube Music / Apple Music / Spotify — whichever Siri has learned as the default media provider. Siri correctly identifies the Abbay application by name (e.g. `"play on Abbay"` returns `"Abbay hasn't added support for that"` rather than misrouting), but `"play in Abbay"` is intercepted by Siri's media-domain router before AppShortcuts matching runs.

**Why:** Siri's "play" verb activates the media-domain router, which prefers `INPlayMediaIntent` providers (the SiriKit Media domain). v1 ships only `AppIntents` / `AudioPlaybackIntent`, not `INPlayMediaIntent`. The media router does not consider AppShortcuts phrases for "play X" cold-start.

**Workaround for users:**
- Use a non-"play" verb: `"Hey Siri, continue audiobook in Abbay"` cold-launches and resumes.
- Or open the app once, then say `"Hey Siri, play in Abbay"` — AppShortcuts win the priority while the process is alive.

**Phase-2 fix:** Ship `INPlayMediaIntent` extension. See `2026-05-17-sirikit-media-providers.md` for the full implementation plan.

---

## 2. Cold-launch-during-call crashes the app

**What fails:** With Abbay **not running** AND an active phone call (or FaceTime audio, or Focus mode with audio restrictions, or another app actively narrating), any Siri-launched intent crashes at launch. The user perceives no playback and no spoken response.

**Why:** Existing `AppDelegate.application(_:didFinishLaunchingWithOptions:)` calls `try AVAudioSession.sharedInstance().setActive(true)` and `fatalError`s in the catch branch. When another app holds the audio session, that activation throws. The intent body never runs. v1 inherits the existing app's behavior (this is not Siri-specific; the same crash would happen on normal cold-launch playback during a call).

**Workaround for users:**
- Wait until the call / Focus / narration ends, then invoke Siri.
- Or tap the Abbay icon manually after the audio session is free.

**Phase-2 fix:** Replace the `fatalError` in `AppDelegate` with a launch-state flag readable from intent bodies; speak `"Audio temporarily unavailable. Try again in a moment."` instead of crashing. Cross-process flag location depends on whether the phase-2 `AppIntentsExtension` lands first or simultaneously — see spec's "Phase-2 migration notes" for the dependency.

---

## 3. `PlayBookByNameIntent` is a two-step Siri interaction, not one-shot

**What fails:** User cannot say `"Hey Siri, play Harry Potter in Abbay"` in a single utterance. The intent's phrases are `"Play audiobook in Abbay"` / `"Pick audiobook in Abbay"` — Siri then prompts `"Which audiobook?"` and the user names the book in a second utterance.

**Why:** Xcode's `appintentsmetadataprocessor` rejects `@Parameter var bookName: String` inside an `AppShortcut` phrase interpolation with `error: Invalid parameter type. AppEntity and AppEnum are the only allowed types`. v1 keeps the parameter as `String` (instead of switching to `AppEntity`) to preserve the spec-locked no-match dialog with input echo: `"No audiobook matches '<input>'."`. With an `AppEntity` parameter, `EntityStringQuery.entities(matching:)` returns `[]` on miss, and the system speaks its own canned no-match dialog rather than ours.

**Workaround for users:**
- Two-step Siri flow works as documented above.
- Or invoke from the Shortcuts app, which can accept a String input via its UI.

**Phase-2 fix:** Same as #1 — `INPlayMediaIntent` extension. `INMediaSearch.mediaName` is an arbitrary String the user can speak in one utterance, AND the SiriKit response definition supports a fully custom no-match dialog with input echo. Solves both constraints at once.

---

## 4. Security-scoped URLs do not round-trip across process death

**What fails:** Books imported via the Files document picker carry a security-scoped URL. After the app process exits, `URL.absoluteString` saved in `LastPlayedStore` no longer carries that scope when re-built via `URL(string:)`. Cold-launch `ResumeAbbayIntent` may receive a URL with no scoped access; `LoadAudioUseCase.execute(url:)` may then return nil, and the user hears `"Cannot find that audiobook..."` even though the file is present on disk.

**Why:** This is pre-existing behavior in the host app — `Player.updatePlayItem` calls `url.startAccessingSecurityScopedResource()` because the URLs come from the document picker, and `absoluteString` is not the right persistence format for scoped resources (`URL.bookmarkData(options: .minimalBookmark)` is). v1 does not change this — Siri inherits the gap from the existing playback path.

**Workaround for users:**
- After cold-launch failure, open Abbay and tap a book once. From that point on the in-process URL is scoped and Siri works.
- The stuck-state-clear in `ResumeAbbayIntent` already handles the dialog gracefully (no silent failure, no loop) — see scope-table behavior.

**Phase-2 fix:** Persist `AudioModel.bookmarkData` (the field already exists on the model) and resolve to a fresh scoped URL at read time. Out of scope for the Siri PR.

---

## 5. AppShortcut phrase entity-parameter restriction

**What fails:** Phrase interpolation like `"Play \(\.$bookName) in Abbay"` requires `bookName` to be an `AppEntity` or `AppEnum`, not a `String`. Direct AppIntents-only path to "Play <arbitrary content name> in App" is blocked.

**Why:** Apple platform constraint. The `appintentsmetadataprocessor` enforces this at build time. Confirmed across multiple Apple Developer Forums threads (#729773, #757298) and community blog posts.

**Workaround:** Drop the parameter from the phrase (the v1 choice) OR switch to `AppEntity` (loses custom no-match dialog). v1 picked the first; phase-2 `INPlayMediaIntent` makes both points moot.

**Phase-2 fix:** Same as #1, #3 — `INPlayMediaIntent`.

---

## 6. iOS 17 minimum deployment target

**What fails:** Abbay no longer runs on iOS 15 or iOS 16 devices (iPhone 7 / 8 / X — devices that won't get iOS 17).

**Why:** `AudioPlaybackIntent` requires iOS 17.0+. The v1 design considered an iOS-16 fallback path (gate `AudioPlaybackIntent` conformance behind `@available(iOS 17, *)` and fall back to plain `AppIntent` with `openAppWhenRun = false` on iOS 16) but rejected it as documented in the spec: doubles maintenance surface for a small remaining device population, and phase-2 work is iOS-17-first in Apple's docs anyway.

**Workaround for users:** Update to a device running iOS 17 or later.

**Phase-2 fix:** None planned. If iOS-15/16 user share is later shown to be material, the fallback path is additive — `@available` gates around the conformance and adjust the cold-start contract for the iOS-16 branch.

---

## 7. CarPlay scene routing behavior not pinned by Apple docs

**What fails:** When CarPlay is connected and Siri is invoked on the phone, it's not pinned by Apple whether the iPhone foregrounds the UI or stays in background while playback continues in the CarPlay scene. `AudioPlaybackIntent` is documented to run in the app process, but specific CarPlay-vs-iPhone scene routing depends on which `UIScene` is active.

**Why:** Apple docs do not explicitly cover this routing case for `AudioPlaybackIntent`. The plan's manual verification checklist (Task 15 Step 5) instructs an on-device observation; both outcomes are accepted as v1 behavior.

**Workaround for users:** None needed — playback works either way. The cosmetic question is whether the iPhone wakes up while connected to CarPlay.

**Phase-2 fix:** If on-device observation reveals unwanted iPhone foregrounding, add an explicit `CPTemplateApplicationScene` routing hook to suppress UI wake-up.

---

## 8. No localization of Siri dialog strings

**What fails:** All five intent dialogs are hard-coded English strings (`"Add a book in Abbay first."`, `"Paused."`, etc.). Users on non-English Siri devices hear English regardless of system language.

**Why:** Localization was an explicit non-goal in the v1 spec. The dialog constants are exposed as `static let` / `static func` on each intent, so a localization pass is additive when needed.

**Workaround for users:** None.

**Phase-2 fix:** Replace `static let foo = "..."` with `static let foo: LocalizedStringResource = "..."` and change `IntentDialog(stringLiteral: Self.foo)` to `IntentDialog(Self.foo)`. Unit tests assert literal English strings today; localization rework would also adapt the tests to assert against the localized resource bundle.

---

## 9. No live disambiguation when multiple library titles match

**What fails:** If the user says `"play Harry Potter in Abbay"` and the library has both `"Harry Potter and the Sorcerer's Stone"` and `"Harry Potter and the Chamber of Secrets"`, the fuzzy matcher picks one (last-played wins, then library-index ascending) and plays it without asking the user to choose.

**Why:** Explicit non-goal in the v1 spec ("Disambiguation flow when multiple titles match"). Siri AppIntents' disambiguation API exists for `AppEntity`-typed parameters, but v1 uses `String` for the reasons in #3 and #5.

**Workaround for users:** Speak more of the title to break the tie (`"play Harry Potter chamber of secrets in Abbay"` → contains-match wins on the more specific title).

**Phase-2 fix:** Comes with `INPlayMediaIntent` — `INPlayMediaMediaItemResolutionResult.disambiguation(with:)` lets the handler return multiple candidates and Siri prompts the user to choose.

---

## 10. AppShortcuts discoverability requires one app launch

**What fails:** Until the user has launched the Abbay binary with v1 installed at least once, Siri does not know any of the phrases are registered. Saying `"Hey Siri, play in Abbay"` before the first launch routes to the default media app (same outcome as #1, but for a different reason).

**Why:** iOS indexes `AppShortcutsProvider` at app launch; Siri's phrase recognizer pulls from that index.

**Workaround for users:** Launch the app once after updating. No specific in-app action needed — the launch itself triggers indexing.

**Phase-2 fix:** None directly. AppShortcuts indexing is an iOS-managed step; the user must run the app once after install. Documenting it in the App Store release notes helps.

---

## 11. `IntentDialog` text is not introspectable from tests

**What fails:** Our unit tests assert observable side effects (mock player calls, store state, loader calls) rather than the spoken dialog string. The dialog wording is verified only via the `dialogConstants_matchSpecVerbatim` tests (which assert the `static let` constants directly) and via the manual on-device checklist.

**Why:** Apple's `IntentDialog` struct does not expose its text via public API. `String(describing:)` returns a debug description that may or may not include the literal. Side-effect testing is the most reliable signal.

**Workaround for testers:** Manual verification (plan Task 15) exercises every spoken dialog branch.

**Phase-2 fix:** If Apple adds a public accessor in a future SDK, our tests can incorporate it. For now, the constant-extraction pattern is the durable workaround.

---

## 12. Manual Siri training may be needed in edge phonetics cases

**What fails:** Siri's speech-to-text occasionally misparses `"Abbay"` as `"a bay"`, especially via on-device dictation. Confirmed at v1 ship time: spoken `"play in abbay"` sometimes routes to YouTube Music playing a song titled "a bay". Typed Siri input recognizes `"abbay"` correctly with capital A.

**Why:** Generic STT phonetic ambiguity. App name `"Abbay"` is not in iOS's pronunciation dictionary. `\(.applicationName)` placeholder resolves via `CFBundleName` / `CFBundleDisplayName`.

**Workaround for users:**
- Shortcuts app → tap an Abbay shortcut → "Add Custom Phrase" → record the phrase in the user's own voice. Trains Siri for that user.
- Or use non-"play" verbs that don't trigger the media-router fast path (see #1).

**Phase-2 fix:** Consider setting `CFBundleDisplayName` to something Siri's STT parses more reliably (e.g. `"Abbay Audiobooks"`) — needs marketing call. Alternatively, ship a pronunciation hint via `LocalizedStringResource(_, inflect:)` once Apple makes that API broadly available for `AppShortcutsProvider` phrases.

---

## Summary table

| # | Limitation | Cause | Phase-2 Fix |
| --- | --- | --- | --- |
| 1 | Cold-start "play" → wrong app | Siri media-router intercepts "play" verb | `INPlayMediaIntent` extension |
| 2 | Cold-launch-during-call crash | `AppDelegate` `fatalError` on session-active throw | Launch-state flag + dialog |
| 3 | `PlayBookByNameIntent` is two-step | String not allowed in AppShortcut phrase interpolation | `INPlayMediaIntent` |
| 4 | Security-scoped URL round-trip | `absoluteString` doesn't carry scope | `bookmarkData` resolution |
| 5 | AppShortcut entity-parameter restriction | Apple platform constraint | `INPlayMediaIntent` |
| 6 | iOS 17 minimum | `AudioPlaybackIntent` is iOS 17+ | None planned |
| 7 | CarPlay routing not pinned | Apple docs gap | `CPTemplateApplicationScene` hook if needed |
| 8 | English-only dialogs | Explicit v1 non-goal | `LocalizedStringResource` migration |
| 9 | No multi-match disambiguation | Explicit v1 non-goal; String param | `INPlayMediaIntent.disambiguation` |
| 10 | First-launch indexing requirement | iOS-managed AppShortcuts index | None — release-notes hint |
| 11 | `IntentDialog` text not introspectable | Apple API gap | None until SDK adds accessor |
| 12 | "Abbay" phonetic ambiguity | STT dictionary gap | Possibly `CFBundleDisplayName` rename / pronunciation hint |

Eleven of twelve have a concrete fix path. Item 6 is the only "by design forever" limitation. Items 1, 3, 5, 9 all share the same fix (`INPlayMediaIntent`), so the phase-2 extension single-handedly resolves four of the twelve.
