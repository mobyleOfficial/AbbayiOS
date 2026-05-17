# PlayMediaIntent.intentdefinition TODO

**Status:** Blocked at T21 — requires Xcode UI; cannot be created from a
Bash/Swift script. The agent that ran the autonomous TDD pipeline for
phase 2 stopped here and continued with T22 using plain
`INPlayMediaIntentResponse(code: .failureUnknownMediaType, ...)` codes
instead of the custom Response template the design spec calls for.

## What needs to be done in Xcode

1. Open `Abbay.xcodeproj` in Xcode.
2. Right-click the `AbbayIntents` group → `New File…` → `SiriKit Intent
   Definition File` → name `PlayMediaIntent`.
3. In the `.intentdefinition` editor:
   - Add a Response.
   - Add Response Parameter `mediaName` (String) — used for input echo
     in the no-match dialog.
   - Add Failure Templates:
     - `unavailable`: `"Audio temporarily unavailable. Try again in a moment."`
     - `noMatch`: `"No audiobook matches '${mediaName}'."`
     - `emptyLibrary`: `"Add a book in Abbay first."`
4. Confirm Xcode generates `PlayMediaIntentResponse` Swift bindings with
   case bindings.
5. Verify the file gets included in the `AbbayIntents` target sources
   (if xcodegen does not pick it up, add an explicit `path:` entry to
   `project.yml`).

## What needs to change in `PlayMediaIntentHandler.swift` after T21

`PlayMediaIntentHandler.handle(intent:completion:)` currently returns:

```swift
completion(INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil))
```

for the `LaunchStateFlag.isUnavailable()` branch. Once the
`.intentdefinition` is in place and Xcode generates the
`PlayMediaIntentResponse` Swift class, replace that line with the
generated `PlayMediaIntentResponse.unavailable(...)` case so Siri reads
the spec-locked dialog from the Response template.

## Why this is blocked outside Xcode

`.intentdefinition` is an Xcode-managed binary plist + generated Swift
sources. The plist format is partially documented but the generated
Swift bindings (case-by-case `PlayMediaIntentResponse` cases) are
emitted by Xcode's `intentbuilderc` at build time and are not part of
the public file format.

## Manual provisioning step

`com.apple.developer.siri` capability must be enabled on the parent
app provisioning profile in the Apple Developer portal before this
extension can launch on a real device. Tracked separately from this
TODO.
