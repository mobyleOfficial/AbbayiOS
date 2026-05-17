# Research: How third-party iOS media apps implement "Hey Siri, play X on AppName"

**Date:** 2026-05-17
**Trigger:** v1 Siri AppIntents implementation (PR #76 / #77) discovered at runtime that cold-start `"Hey Siri, play in Abbay"` routes to the system's default media app (YouTube Music) instead of `ResumeAbbayIntent`. Question raised: how do Spotify, YouTube Music, Audible solve the same problem?

**Status:** Reference only. Seed for the phase-2 `INPlayMediaIntent` extension plan. Not an executable plan itself.

---

## The shipping pattern (Spotify, YouTube Music, Pandora, Audible, etc.)

All major third-party iOS media apps use the **legacy SiriKit Media domain** — `INPlayMediaIntent` from the `Intents` framework — implemented in a **Siri Intents app extension**. The extension's `Info.plist` has an `NSExtension` of type `INExtension` declaring `INPlayMediaIntent` under `IntentsSupported`. This is the path Apple introduced in iOS 13 for exactly this UX (Spotify and Pandora launched on it that year). It remains the **only first-class one-shot path** for cold-start media voice routing as of iOS 18.

### How the wire protocol works

1. Siri parses the spoken utterance and hands the app a populated `INMediaSearch` with `mediaName`, `artistName`, `albumName`, `mediaType`, etc.
2. The app implements `INPlayMediaIntentHandling.resolveMediaItems(for:with:)` and returns `[INPlayMediaMediaItemResolutionResult]` — typically one `.success(with: INMediaItem(...))` per match, or `.unsupported(forReason: .unsupportedMediaType)` for no match.
3. The app handles playback either in the extension's `handle(intent:completion:)` callback or via `continueInApp` (background-launch the host app to play the audio in-process).
4. After successful playback, donate an `INPlayMediaIntent` interaction so Siri's preferred-media-app learning can suggest the app next time.

### Apple's status on the API (iOS 18.x)

Apple's developer support page "[Deprecated SiriKit Intent Domains](https://developer.apple.com/support/deprecated-sirikit-intent-domains)" lists CarPlay, Lists/Notes, Payments, Photos, Visual Codes, VoIP, and Ride Booking as deprecated. **The Media domain (INPlayMediaIntent) is explicitly NOT on that list** and remains the supported path. Recent Apple Developer Forums threads (e.g. FB14872048 from Aug 2024 on `INMediaSearch` reliability) show Apple staff still triaging it as a live API and not pointing developers to an AppIntents replacement.

WWDC24 session 10133 ("Bring your app to Siri") states verbatim:

> If your app overlaps with an existing SiriKit Domain, SiriKit Domains are still the best ways for you to enable these kinds of features. If your app does not overlap with an existing SiriKit Domain, AppIntents is the right framework for you.

Media overlaps. So Apple's own guidance is: **use SiriKit Media**.

---

## Why `AudioPlaybackIntent` + `AppEntity` cannot match the UX

Confirmed at our implementation time and corroborated by Apple Developer Forums threads:

- `@Parameter var foo: String` cannot be substituted into an App Shortcut phrase. Xcode's `appintentsmetadataprocessor` rejects it with: `error: Invalid parameter type. AppEntity and AppEnum are the only allowed types`. Community confirmation across Apple Developer Forums threads (e.g. "AppIntent parameter value can't…" #729773, "Siri not calling AppIntents" #757298), Lickability, createwithswift, and BleepingSwift posts.
- With `EntityStringQuery.entities(matching:)`, returning `[]` causes the system to speak its own canned "I couldn't find…" dialog. Throwing from `entities(matching:)` works for `perform()`-level failures but does not let you replace Siri's resolution-phase no-match prompt with a custom string.
- The new iOS 18 **assistant schemas** (e.g. `AssistantSchemas.BooksIntent.playAudiobook`, `playMedia`) are still backed by `AppEntity` parameters, not arbitrary strings — they get matching/disambiguation from Apple Intelligence training rather than from a String slot. They're additive on top of AppIntents and require Apple Intelligence-eligible devices (iOS 18.1+). They do not solve the no-match dialog or input-echo problem.
- Even with `AudioPlaybackIntent` conformance, the **"play" verb cold-routes through Siri's media-domain router**, which prefers `INPlayMediaIntent` providers. Confirmed on device: `"Hey Siri, play in Abbay"` from a killed app state routes to YouTube Music; non-"play" verbs ("continue audiobook in Abbay", "next chapter in Abbay") cold-route correctly through AppShortcuts.

---

## The recommended real-world pattern: hybrid

Spotify-class apps ship **both** systems:

- **`INPlayMediaIntent` (extension target)** — for the spoken "play X on AppName" route, including cold-start. Wins the media-router priority.
- **`AppIntents` (in-app)** — for Shortcuts, widgets, Control Center, Now Playing controls, donations.

Donations are framework-independent: `INPlayMediaIntent.donate()` from the legacy side or `IntentDonationManager` via `AudioPlaybackIntent` from the modern side both feed Siri's preferred-app learning. No App Store review issues; coexistence is the production norm.

---

## System "media provider" registration

The system "Hey Siri, play [artist]" routing — no app name in the utterance — is keyed off `INPlayMediaIntent` support and iOS 14.5+ preferred-media-app learning. There is no public AppIntents-native equivalent as of iOS 18.x. HomePod 17.4 added preference learning on the device side but the protocol the app implements is unchanged.

---

## Recommendation for Abbay (phase 2)

Implement `INPlayMediaIntent` in a Siri Intents extension target alongside the existing AppIntents. Concrete shape:

1. **New extension target** `AbbayIntents` (or similar) with `type: app-extension`, `principalClass: $(PRODUCT_MODULE_NAME).IntentHandler`. xcodegen entry: `INExtension` under `NSExtension.NSExtensionAttributes.IntentsSupported` listing `INPlayMediaIntent`.
2. **Add the Siri capability** to the main app target (`com.apple.developer.siri` entitlement, `NSSiriUsageDescription` in Info.plist).
3. **`IntentHandler.swift`** subclasses `INExtension` and returns an `INPlayMediaIntentHandling` instance for `INPlayMediaIntent` requests.
4. **`PlayMediaIntentHandler.swift`** implements:
   - `resolveMediaItems(for:with:)` — search the library by `intent.mediaSearch?.mediaName`. On hit, return `.success(with: INMediaItem(identifier: url.absoluteString, title:, type: .audioBook, artwork: nil, artist:))`. On miss, return a `.unsupported(forReason:)` and emit an `INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity:)` carrying a custom-localized response template (created via the `.intentdefinition` Response parameter; preserves the spec's `"No audiobook matches '\(input)'."` echo — exactly the wording AppIntents blocks today).
   - `handle(intent:completion:)` — return `.success` with a `userActivity` set up for `NSUserActivityTypeBrowsingWeb` → `continueInApp` so the host process foregrounds into background-audio context and plays the resolved URL. Alternatively, the extension can play directly via AVPlayer in-process if the audio session is shareable.
5. **Cross-process state** — extension reads the library via shared `LoadAllAudiosUseCase` / `LoadAudioUseCase`, which must be reachable from the extension binary. Two implementation paths:
   - Extract shared model + use-case code into an embedded framework (`AbbayKit`) and link it from both targets. Heavier, but the same shape Apple's sample code uses. The stashed v0 attempt on this branch already explored this.
   - Keep the extension code self-contained (own Core Data stack pointing at the App Group store). Lighter, more duplication.
6. **App Group** — Core Data store + `LastPlayedStore` move to `UserDefaults(suiteName: "group.com.edyuto.abbay")` so both processes see the same library and last-played pointer. Migration plan already pinned in the v1 spec.
7. **Donations** — after successful resolve, donate `INPlayMediaIntent` via `INInteraction(intent:response:).donate()`. Feeds Siri's preferred-media-app learning.
8. **AppIntents stay** — Resume / Pause / Next / Previous / PlayBookByName from v1 keep working for Shortcuts and in-app voice while the new extension handles cold-start "play".

### Trade-offs

| Path | LOC | Surface | Custom no-match dialog | Cold-start one-shot |
| --- | --- | --- | --- | --- |
| `INPlayMediaIntent` extension (this plan) | ~80–150 + extension scaffold | Adds extension target + Siri entitlement + App Group | Yes (via response definition) | Yes |
| `AppEntity`-based AppIntents only | smaller, no extension | Modern only, in-process | No (system speaks canned dialog) | No (loses to media router on "play") |
| Assistant schemas (`playAudiobook`) | smaller | iOS 18.1+, Apple Intelligence gate | No (still AppEntity-based) | Partial — still loses to media router for users without AI eligibility |

### App Store / capability impact

- Adds the Siri capability to the main app (profile regen). No App Store review issue — every major media app ships this.
- Extension binary adds ~tens of KB to IPA.
- `NSSiriUsageDescription` becomes required (was explicitly dropped from v1 — see spec). String value should be the same one the v0 attempt used: `"Abbay uses Siri to play your audiobooks and control playback when you say things like 'Play on Abbay' or 'Play next chapter in Abbay'."` (or similar).

### Phase-2 plan dependencies

This work composes with two other phase-2 items already pinned in the v1 spec:

- **App Group + `LastPlayedStore` migration** — required for the extension to see the same last-played pointer the main app writes. The v1 spec's "Phase-2 migration notes" already documents the seed-then-write ordering for zero-loss migration.
- **`AppDelegate.fatalError` → launch-state flag** — also requires the App Group `UserDefaults` because the flag must be readable from the extension. Cross-process dependency note already pinned in the v1 spec.

Order of work: App Group migration first (unlocks the others); then INPlayMediaIntent extension; then graceful-launch-flag.

---

## Sources

### Apple primary docs

- [`INPlayMediaIntent` — Apple Developer Documentation](https://developer.apple.com/documentation/intents/inplaymediaintent)
- [`INPlayMediaIntentHandling` — Apple Developer Documentation](https://developer.apple.com/documentation/intents/inplaymediaintenthandling)
- [`resolveMediaItems(for:with:)` — Apple Developer Documentation](https://developer.apple.com/documentation/sirikit/inplaymediaintenthandling/3074275-resolvemediaitems)
- [Deprecated SiriKit Intent Domains — Apple Developer](https://developer.apple.com/support/deprecated-sirikit-intent-domains) (Media domain NOT listed)
- [`AudioPlaybackIntent` — Apple Developer Documentation](https://developer.apple.com/documentation/appintents/audioplaybackintent)
- [Integrating actions with Siri and Apple Intelligence — Apple Developer](https://developer.apple.com/documentation/appintents/integrating-actions-with-siri-and-apple-intelligence)
- [`AssistantSchemas.BooksIntent.playAudiobook` — Apple Developer Documentation](https://developer.apple.com/documentation/appintents/assistantschemas/booksintent/playaudiobook?language=_6)
- [Migrating from SiriKit Intents to App Intents — Apple Developer](https://developer.apple.com/documentation/widgetkit/migrating-from-sirikit-intents-to-app-intents) (widgets only)

### WWDC sessions

- [WWDC22 session 10032 — Dive into App Intents](https://developer.apple.com/videos/play/wwdc2022/10032/)
- [WWDC24 session 10133 — Bring your app to Siri](https://developer.apple.com/videos/play/wwdc2024/10133/)
- [WWDC19 session 207 — Introducing SiriKit Media Intents](https://developer.apple.com/videos/play/wwdc2019/207/)
- [WWDC20 session 10061 — Expand your SiriKit Media Intents to more platforms](https://developer.apple.com/videos/play/wwdc2020/10061/)
- [Apple Tech Talk 10854 — Integrate SiriKit Media Intents with HomePod](https://developer.apple.com/videos/play/tech-talks/10854/)

### Apple Developer Forums

- [INPlayMediaIntent mediaSearch reliability (Aug 2024, FB14872048)](https://forums.developer.apple.com/forums/thread/762196)
- [AppIntent parameter value can't be a String for voice phrases (#729773)](https://developer.apple.com/forums/thread/729773)
- [Siri not calling AppIntents (parameter type restrictions, #757298)](https://developer.apple.com/forums/thread/757298)

### Third-party

- [Audible — "Hey Siri, Play Audible" newsroom](https://www.audible.com/about/newsroom/hey-siri-play-audible)
- [Spotify Support — Siri and Spotify](https://support.spotify.com/us/article/siri-and-spotify/)
- [Spotify Community — Implement SiriKit Media API in iOS 13](https://community.spotify.com/t5/Closed-Ideas/iOS-Implement-SiriKit-Media-API-in-iOS-13/idi-p/4799827)
- [How-To Geek — How to Use Spotify with Siri on iPhone](https://www.howtogeek.com/656933/how-to-use-spotify-with-siri-on-iphone/)
- [MacRumors — iOS 14.5: Set Preferred Music Streaming Service With Siri](https://www.macrumors.com/how-to/set-preferred-music-streaming-service-siri/)
- [9to5Mac — HomePod 17.4 default streaming app](https://9to5mac.com/2024/03/04/homepod-17-4-default-streaming-app/)
- [WWDCNotes — WWDC22 session 10032 notes](https://www.wwdcnotes.com/notes/wwdc22/10032/)
- [Lickability — Mastering App Intents: Querying](https://lickability.com/blog/app-intents/)
- [Create With Swift — Creating App Intents using Assistant Schemas](https://www.createwithswift.com/creating-app-intents-using-assistant-schemas/)
