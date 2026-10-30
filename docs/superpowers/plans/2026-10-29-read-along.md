# Read-along (experimental) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An opt-in, iOS 26+ read-along mode: the player's cover square flips to the text being
read, transcribed on the device from the audiobook's own audio, with the current line and spoken
word highlighted.

**Architecture:** A pure transcript model (timed lines and words in book time) is produced by a
`ReadAlongTranscribing` protocol (live: `SpeechAnalyzer` + `SpeechTranscriber`; stub: canned
lines), cached on disk by `ReadAlongStore`, and driven per shown book by a `@MainActor`
`ReadAlongSession` that runs only while the text is on screen. `ReadAlongView` replaces the cover
in `PlayerView` and reads a 0.1 s `TimelineView` clock off the player only while visible.

**Tech Stack:** Swift 5, SwiftUI, Observation, AVFoundation, Speech (`SpeechAnalyzer`,
`SpeechTranscriber`, `AssetInventory`, iOS 26+), XCTest / XCUITest, XcodeGen, fastlane.

**Spec:** `docs/superpowers/specs/2026-10-29-read-along-design.md` (read it first; this plan
argues from it).

## Global Constraints

- Deployment target stays **iOS 17.0**. Every Speech API use is inside `@available(iOS 26, *)` /
  `if #available(iOS 26, *)`. On iOS 17–25 no Experimental section, no pill, no read-along code runs.
- **No** `NSSpeechRecognitionUsageDescription`, `NSMicrophoneUsageDescription`, no
  `SFSpeechRecognizer.requestAuthorization`, no microphone. If transcription turns out to need
  authorization, stop and ask the owner.
- Nothing runs, transcribes or downloads while **Read-along** is off, or while the text isn't on
  screen. No new network host.
- Transcription reads only files on the device: never streams, never starts a book download.
- Every user-visible string in `Abbay/Resources/Localizable/Localizable.xcstrings` with `en` and
  `pt-BR`, reached through the `Localizable` enum (`Abbay/Resources/Localizable/Localizable.swift`).
- New accessibility ids in `Abbay/Core/AccessibilityID.swift`, launch arguments in
  `Abbay/Core/LaunchArgument.swift` (and added to `LaunchArgument.all`).
- Work in a worktree under `.worktrees/` (never `/tmp`), branch `feature/read-along` from `develop`.
  Commits carry **no** `Co-Authored-By` trailer. Push and open the PR only when the owner asks.
  The PR targets `develop` and **does not merge until the owner has tested an OTA build**.
- Tests on a dedicated simulator with `-parallel-testing-enabled NO`. Gate: `bundle exec fastlane
  verify` (SwiftLint strict, unit, UI).

## Review Focus

1. **The book changes under an open text view** (Siri/CarPlay switches book, or Play on another
   book while the screen follows the loaded book): the session must stop and restart for the new
   book, never show book A's text over book B. → test in Task 6.
2. **A seek far ahead or back into untranscribed audio** (scrubber, chapter tap, skip): the
   current line must come from the new position within the same "Preparing" budget, not after the
   old run catches up. → test in Task 6.
3. **The text is shown for a book that isn't the loaded one** (opened from a row, not playing): it
   follows the saved position, and a line tap does nothing rather than seeking the loaded book. →
   test in Task 8.
4. **Feature turned off while the text is showing / while transcribing**: the run stops, the pill
   and text disappear, all transcripts are deleted, and no write lands after the delete. → test in
   Task 6.
5. **Mid-chapter download finishing** (needs-download state, then the current chapter's file
   arrives): the text appears by itself without the user flipping the pill. → test in Task 6.

---

### Task 1: Transcript model and highlight lookup

**Files:**
- Create: `Abbay/Core/ReadAlong/ReadAlongTranscript.swift`
- Test: `AbbayTests/ReadAlongTranscriptTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct ReadAlongWord: Codable, Equatable { let text: String; let start: Double; let end: Double }
  struct ReadAlongLine: Codable, Equatable { let start: Double; let end: Double; let words: [ReadAlongWord]
      var text: String }               // words joined by " "
  struct ReadAlongSpan: Codable, Equatable { var start: Double; var end: Double }
  struct ReadAlongPosition: Equatable { let line: Int; let word: Int? }
  struct ReadAlongTranscript: Codable, Equatable {
      var language: String               // BCP-47, e.g. "en-US"
      private(set) var lines: [ReadAlongLine]   // sorted by start, no duplicates
      private(set) var covered: [ReadAlongSpan] // merged, sorted: book time already transcribed
      init(language: String)
      mutating func add(_ lines: [ReadAlongLine], covering span: ReadAlongSpan)
      func isCovered(_ time: Double) -> Bool
      func position(at time: Double) -> ReadAlongPosition?
  }
  ```
  All times are **book time** in seconds.

- [ ] **Step 1: Write the failing tests**

```swift
final class ReadAlongTranscriptTests: XCTestCase {
    private func line(_ start: Double, _ words: [String]) -> ReadAlongLine {
        let parts = words.enumerated().map { i, w in ReadAlongWord(text: w, start: start + Double(i), end: start + Double(i) + 0.8) }
        return ReadAlongLine(start: start, end: start + Double(words.count), words: parts)
    }

    func test_position_insideAWord_returnsLineAndWord() {
        var t = ReadAlongTranscript(language: "en-US")
        t.add([line(10, ["Mr.", "and", "Mrs."]), line(20, ["Dursley"])], covering: .init(start: 0, end: 30))
        XCTAssertEqual(t.position(at: 11.2), ReadAlongPosition(line: 0, word: 1))
    }
    func test_position_betweenWordsOfALine_keepsLine_noWord() {
        // 11.9 is after "and" ends (11.8) and before "Mrs." starts (12.0)
        XCTAssertEqual(sample.position(at: 11.9), ReadAlongPosition(line: 0, word: nil))
    }
    func test_position_inAGapBetweenLines_holdsThePreviousLine() {
        XCTAssertEqual(sample.position(at: 15), ReadAlongPosition(line: 0, word: nil))
    }
    func test_position_beforeFirstLine_isNil() { XCTAssertNil(sample.position(at: 5)) }
    func test_add_overlappingRuns_mergesCoveredAndDropsDuplicateLines() {
        var t = ReadAlongTranscript(language: "en-US")
        t.add([line(10, ["a"])], covering: .init(start: 0, end: 15))
        t.add([line(10, ["a"]), line(20, ["b"])], covering: .init(start: 8, end: 25))
        XCTAssertEqual(t.lines.map(\.start), [10, 20])
        XCTAssertEqual(t.covered, [ReadAlongSpan(start: 0, end: 25)])
    }
    func test_add_outOfOrderRuns_keepsLinesSorted() { /* add 100…, then 0…; assert starts ascending */ }
    func test_isCovered() { /* covered 0–25 and 60–70: 24 true, 30 false, 65 true */ }
    func test_codableRoundTrip() { /* encode/decode with JSONEncoder equals original */ }
}
```
(`sample` is the two-line transcript of the first test, as a computed property.)

- [ ] **Step 2: Run, expect FAIL** (`ReadAlongTranscript` undefined)

Run: `xcodebuild test -project Abbay.xcodeproj -scheme Abbay -destination 'platform=iOS Simulator,name=<your sim>' -parallel-testing-enabled NO -only-testing:AbbayTests/ReadAlongTranscriptTests`

- [ ] **Step 3: Implement** in `ReadAlongTranscript.swift`. `add` replaces any existing line whose
  `start` is within 0.05 s of an incoming one; `position(at:)` is a binary search for the last line
  with `start <= time`, then the word with `start <= time < end`.
- [ ] **Step 4: Run, expect PASS**
- [ ] **Step 5: Commit** `feat(read-along): transcript model and highlight lookup (#192)`

---

### Task 2: Language mapping, candidates and the detection pick

**Files:**
- Create: `Abbay/Core/ReadAlong/ReadAlongLanguage.swift`
- Test: `AbbayTests/ReadAlongLanguageTests.swift`

**Interfaces:**
- Produces:
  ```swift
  enum ReadAlongLanguage {
      /// LibriVox gives "eng", "English", "por", "Portuguese"…: a language code ("en"), or nil.
      static func languageCode(fromLibriVox value: String) -> String?
      /// Candidate locale ids for detection, in order, deduplicated, only ones in `installed`:
      /// the app language, then `preferred` (device), then English.
      static func candidates(appLanguage: String?, preferred: [String], installed: [String]) -> [String]
      /// The locale with the best mean confidence, if it reaches `minimumConfidence`; else nil.
      static func best(_ scores: [String: Double], minimumConfidence: Double = 0.5) -> String?
      /// The installed/supported locale that matches a language code ("pt" → "pt-BR" if offered).
      static func locale(forLanguageCode code: String, in supported: [String], preferredRegion: String?) -> String?
      /// "English", "Português" in the in-app language (`AbbayBundle.locale`).
      static func displayName(_ localeID: String) -> String
  }
  ```

- [ ] **Step 1: Failing tests** — `languageCode(fromLibriVox:)`: `"eng"`→`"en"`, `"English"`→`"en"`,
  `"por"`→`"pt"`, `"Portuguese"`→`"pt"`, `"ger"`→`"de"`, `"German"`→`"de"`, `"Klingon"`→`nil`,
  `""`→`nil`. `candidates(appLanguage: "pt", preferred: ["pt-BR","en-GB"], installed: ["en-US","en-GB","pt-BR"])`
  == `["pt-BR","en-GB","en-US"]`; a candidate not installed is skipped. `best(["en-US":0.9,"pt-BR":0.4])`
  == `"en-US"`; `best(["en-US":0.3])` == `nil`; `best([:])` == `nil`. `locale(forLanguageCode:"pt", in:["pt-BR","pt-PT","en-US"], preferredRegion:"BR")` == `"pt-BR"`; region nil → first match.
- [ ] **Step 2: Run, expect FAIL**
- [ ] **Step 3: Implement.** Names match English names case-insensitively via
  `Locale(identifier: "en").localizedString(forLanguageCode:)` over `Locale.LanguageCode.isoLanguageCodes`;
  3-letter codes via `Locale.Language(identifier:).languageCode?.identifier(.alpha2)` (cover the
  bibliographic `ger`/`fre`/`dut`/`chi` explicitly if Foundation doesn't).
- [ ] **Step 4: Run, expect PASS**
- [ ] **Step 5: Commit** `feat(read-along): language mapping and detection pick (#192)`

---

### Task 3: Settings, on-disk store, and cleanup paths

**Files:**
- Create: `Abbay/Core/ReadAlong/ReadAlongStore.swift`
- Modify: `Abbay/Core/Settings/AppSettings.swift` (keys, properties, effects)
- Modify: `Abbay/Model/UseCases/DeleteAudioUseCase.swift` (`forgetSettingsOnMain`, delete transcript)
- Modify: `Abbay/View/LibriVoxDetail/LibriVoxDetailViewModel.swift` (`start(_:allowsCellular:)`: store the listed language)
- Test: `AbbayTests/ReadAlongStoreTests.swift`, `AbbayTests/AppSettingsTests.swift`,
  `AbbayTests/DeleteAudioUseCaseDownloadsTests.swift` (or a sibling), LibriVox detail VM tests

**Interfaces:**
- Consumes: `ReadAlongTranscript` (Task 1), `ReadAlongLanguage.languageCode(fromLibriVox:)` (Task 2).
- Produces:
  ```swift
  final class ReadAlongStore {               // thread-safe (serial queue); files are JSON
      static let shared: ReadAlongStore      // root: Application Support/ReadAlong, excluded from backup
      init(root: URL)
      func load(bookURL: URL) -> ReadAlongTranscript?
      func save(_ transcript: ReadAlongTranscript, bookURL: URL)
      func delete(bookURL: URL)
      func deleteAll()
  }
  // AppSettings
  enum Key { static let readAlongEnabled = "abbay.settings.readAlong"
             static let readAlongShowsText = "abbay.settings.readAlongShowsText"
             static let readAlongLanguages = "abbay.settings.readAlongLanguages" }
  var readAlongEnabled: Bool          // default false; didSet false → effects?.clearReadAlong()
  var readAlongShowsText: Bool        // default false: cover until the user flips once
  func readAlongLanguage(for url: URL?) -> String?        // a locale id ("pt-BR") or a code hint ("pt")
  func setReadAlongLanguage(_ language: String?, for url: URL?)
  func forgetReadAlong(for url: URL?)                     // drops the book's language
  // SettingsEffects gains: func clearReadAlong()  (Live: ReadAlongStore.shared.deleteAll())
  ```
  File name per book: SHA-256 hex of `bookURL.absoluteString` + `.json` (the book's identity,
  `AudioModel.url`, which doesn't change when a file moves). One transcript per book; its
  `language` says which language it is in.

- [ ] **Step 1: Failing tests**
  - Store: save→load round-trips; two books don't collide; `delete(bookURL:)` removes only that
    book; `deleteAll()` empties the root; `load` of a corrupt file returns nil and deletes it; the
    root has `isExcludedFromBackup == true` after the first save.
  - Settings: `readAlongEnabled` false by default and persisted across a new `AppSettings` on the
    same `InMemoryKeyValueStore`; setting it false calls a spy `clearReadAlong()` once, setting it
    true does not; `readAlongShowsText` persisted; `setReadAlongLanguage("pt-BR", for:)` round-trips
    and `forgetReadAlong(for:)` removes it.
  - Delete: `DeleteAudioUseCase.execute` calls the injected forget closure for each book; the live
    closure also calls `ReadAlongStore.shared.delete(bookURL:)` (inject a store in the test).
  - LibriVox add: after `start` saves the book, `settings.readAlongLanguage(for: model.url) == "en"`
    for a book whose `language` is `"eng"`; nothing stored for `"Klingon"`.
- [ ] **Step 2: Run, expect FAIL**
- [ ] **Step 3: Implement.** The LibriVox VM gets a new init parameter
  `recordLanguage: @escaping (String, URL?) -> Void = { … DependencyContainer.shared.settings.setReadAlongLanguage … }`
  (the same seam style as `cellularPreference`); it stores the language **whether or not
  read-along is on** — it is a hint, not text. `forgetSettingsOnMain` calls `forgetSpeed`,
  `forgetReadAlong` and `ReadAlongStore.shared.delete(bookURL:)`.
- [ ] **Step 4: Run, expect PASS** (also the existing `AppSettingsTests`, `DeleteAudioUseCase*`,
  LibriVox detail tests)
- [ ] **Step 5: Commit** `feat(read-along): settings, transcript store, cleanup on delete and off (#192)`

---

### Task 4: Where the audio is (`ReadAlongAudioSource`)

**Files:**
- Create: `Abbay/Core/ReadAlong/ReadAlongAudioSource.swift`
- Test: `AbbayTests/ReadAlongAudioSourceTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct ReadAlongAudioSource: Equatable {
      struct Segment: Equatable {
          let fileURL: URL?          // nil: not on the device
          let bookStart: Double      // book time where this file's 0 s is
          let duration: Double
          let isSecurityScoped: Bool // an imported file: start/stop accessing around reads
      }
      let segments: [Segment]
      let isLibriVox: Bool
      static func make(for book: AudioModel, root: URL = LibriVoxIdentity.defaultRoot,
                       fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> ReadAlongAudioSource
      func segment(at bookTime: Double) -> Segment?
      func isOnDevice(at bookTime: Double) -> Bool
  }
  ```

- [ ] **Step 1: Failing tests** — a LibriVox `AudioModel` with three chapters where only chapter 1
  is downloaded (temp root with a file at `LibriVoxIdentity.localFileURL`): three segments with
  `bookStart` = each chapter's `startTime`; `isOnDevice(at:)` true only inside chapter 1. An
  imported book (no `librivoxID`) with `fileURL` existing: one segment, `bookStart` 0, duration
  `book.duration`, `isSecurityScoped` true. Imported, file missing: one segment with `fileURL` nil.
  `segment(at:)` past the end returns the last segment; with no segments, nil.
- [ ] **Step 2: Run, expect FAIL**
- [ ] **Step 3: Implement** using `LibriVoxIdentity.isDownloaded(_:bookID:root:)` /
  `localFileURL(for:bookID:root:)` and `AudioModel.fileURL`. For the imported existence check,
  wrap `fileExists` in `startAccessingSecurityScopedResource` (the bookmark is already resolved
  into `resolvedURL` by the mapper).
- [ ] **Step 4: Run, expect PASS**
- [ ] **Step 5: Commit** `feat(read-along): map a book's book time to files on the device (#192)`

---

### Task 5: The transcriber (protocol, live, stub) and language detection

**Files:**
- Create: `Abbay/Core/ReadAlong/ReadAlongTranscribing.swift` (protocol + `ReadAlongModelStatus`)
- Create: `Abbay/Core/ReadAlong/SpeechReadAlongTranscriber.swift` (`@available(iOS 26, *)`)
- Create: `Abbay/DebugSupport/StubReadAlongTranscriber.swift` (`#if DEBUG`; used by unit and UI tests)
- Test: `AbbayTests/SpeechReadAlongTranscriberTests.swift` (integration on the Christmastide fixture)

**Interfaces:**
- Consumes: `ReadAlongLine`/`ReadAlongWord`/`ReadAlongSpan` (Task 1), `ReadAlongAudioSource` (Task 4).
- Produces:
  ```swift
  enum ReadAlongModelStatus: Equatable { case installed, downloadable, unsupported }
  struct ReadAlongChunk: Equatable { let lines: [ReadAlongLine]; let covered: ReadAlongSpan }

  protocol ReadAlongTranscribing: AnyObject, Sendable {
      func supportedLocales() async -> [String]
      func installedLocales() async -> [String]
      func modelStatus(locale: String) async -> ReadAlongModelStatus
      func installModel(locale: String) async throws
      /// Transcribes forward from `startTime` (book time), segment after segment, until the end
      /// of the book, the first segment not on the device (then finishes), or cancellation.
      /// Each chunk carries finished lines and the book-time span now covered.
      func transcribe(_ source: ReadAlongAudioSource, from startTime: Double, locale: String)
          -> AsyncThrowingStream<ReadAlongChunk, Error>
      /// Mean word confidence of `seconds` of audio from `startTime`, for language detection.
      func confidence(_ source: ReadAlongAudioSource, from startTime: Double, seconds: Double,
                      locale: String) async throws -> Double
  }
  ```
  The stub (`StubReadAlongTranscriber`) is configurable: `status`, a `lines(from:to:)` generator
  (default: a line every 4 s, *"Seeded line N of the read-along text"*, words 0.5 s apart), an
  optional per-chunk delay, and recorded calls (`transcribeStarts: [Double]`, `installCalls`).

- [ ] **Step 1: Write the integration test** (it proves the real engine, and answers the open
  question whether it runs in the Simulator):
  ```swift
  @available(iOS 26, *)
  func test_christmastide_firstChapter_producesTimedEnglishLines() async throws {
      try XCTSkipUnless(SpeechTranscriber.isAvailable, "SpeechTranscriber unavailable here")
      let t = SpeechReadAlongTranscriber()
      try XCTSkipUnless(await t.modelStatus(locale: "en-US") == .installed, "en-US model not installed")
      let source = ReadAlongAudioSource(segments: [.init(fileURL: fixtureURL("Christmastide", "m4b"),
                                         bookStart: 0, duration: 144.015, isSecurityScoped: false)], isLibriVox: false)
      var lines: [ReadAlongLine] = []
      for try await chunk in t.transcribe(source, from: 30, locale: "en-US") { lines += chunk.lines }
      XCTAssertGreaterThan(lines.count, 5)
      XCTAssertGreaterThanOrEqual(lines.first!.start, 29.5)           // started at 30 s, in book time
      XCTAssertTrue(lines.allSatisfy { $0.words.allSatisfy { $0.end >= $0.start } })
      XCTAssertEqual(lines.map(\.start), lines.map(\.start).sorted())
  }
  @available(iOS 26, *)
  func test_confidence_englishBeatsPortuguese_onEnglishAudio() async throws { /* skip as above for each model; en-US > pt-BR */ }
  ```
- [ ] **Step 2: Run on the simulator.** Expected: FAIL to compile (type missing). After Step 3,
  record in the PR whether these **ran or were skipped** in the Simulator.
- [ ] **Step 3: Implement `SpeechReadAlongTranscriber`** the way the spike did:
  `SpeechTranscriber(locale:, transcriptionOptions: [], reportingOptions: [], attributeOptions:
  [.audioTimeRange, .transcriptionConfidence])`, `SpeechAnalyzer(modules:)`,
  `AVAudioFile(forReading:)` with `framePosition` set to the start offset, `analyzeSequence(from:)`
  then `finalizeAndFinish(through:)`. Map each final result: one `ReadAlongLine` per result, one
  `ReadAlongWord` per run that has an `audioTimeRange`, times `+ segment.bookStart + startOffset`.
  Yield a chunk per result with `covered` = `start…result.range.end` in book time; after a
  segment finishes, yield its full span as covered (silence counts as covered). Wrap imported files
  in `startAccessingSecurityScopedResource`. Locale strings ↔ `Locale` via
  `SpeechTranscriber.supportedLocale(equivalentTo:)`; model status/installs via
  `AssetInventory.assetInstallationRequest(supporting:)` and `SpeechTranscriber.installedLocales`.
  `confidence` = mean of run confidences over the first `seconds` of results.
- [ ] **Step 4: Implement the stub**, and run the integration tests again: PASS or SKIP (not FAIL).
- [ ] **Step 5: Commit** `feat(read-along): on-device transcriber behind a protocol, plus stub (#192)`

---

### Task 6: `ReadAlongSession`: the per-book state machine

**Files:**
- Create: `Abbay/Core/ReadAlong/ReadAlongSession.swift`
- Create: `Abbay/Core/ReadAlong/ReadAlongCenter.swift` (app-wide services: transcriber, store,
  settings; makes sessions; nil transcriber below iOS 26)
- Modify: `Abbay/Core/DI/DependencyContainer.swift` (+ protocol), `AbbayTests/Mocks/MockDependencyContainer.swift`,
  `Abbay/Core/Playback/PlaybackEnvironment.swift` (inject `ReadAlongCenter` into the environment),
  `Abbay/DebugSupport/DebugOverrides.swift` (`readAlongTranscriber(arguments:)` → stub under `-seedReadAlong`)
- Test: `AbbayTests/ReadAlongSessionTests.swift`

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces:
  ```swift
  enum ReadAlongState: Equatable {
      case preparing                    // detecting, or no line yet at the shown time
      case downloadingModel(String)     // locale id
      case unsupported(String)          // locale id iOS can't transcribe
      case needsDownload                // LibriVox chapter not on the device
      case fileMissing                  // imported file not on the device
      case failed
      case ready                        // the shown time is covered (a line or silence)
  }
  @MainActor @Observable final class ReadAlongCenter {
      init(transcriber: ReadAlongTranscribing?, store: ReadAlongStore, settings: AppSettings)
      var isAvailable: Bool             // transcriber != nil (iOS 26+)
      func makeSession() -> ReadAlongSession
  }
  @MainActor @Observable final class ReadAlongSession {
      private(set) var state: ReadAlongState
      private(set) var transcript: ReadAlongTranscript?
      private(set) var language: String?           // locale id in use
      private(set) var choices: [String]           // supported locales, for the picker
      func show(_ book: AudioModel, at time: Double)  // start or retarget; same book + covered time → no restart
      func timeChanged(_ time: Double)                // jump outside covered & outside the running run's reach → restart there
      func downloadsChanged(_ book: AudioModel)       // re-check needsDownload/fileMissing
      func setLanguage(_ locale: String)              // persist per book, delete transcript, restart
      func stop()                                     // cancel the run; keeps what is saved
  }
  ```
  Language resolution order in `show`: the book's stored setting (`settings.readAlongLanguage(for:)`;
  a bare code like `"en"` is resolved with `ReadAlongLanguage.locale(forLanguageCode:in:preferredRegion:)`
  and saved back as the locale id) → detection (`candidates` from the in-app language,
  `Locale.preferredLanguages`, English, among **installed** locales; `confidence` over 20 s from
  `time`; `best`) → the in-app language's locale. The detected one is saved per book.
  Then: unsupported → `.unsupported`; downloadable → `.downloadingModel` + `installModel`; source
  not on device at `time` → `.needsDownload`/`.fileMissing`; else load the saved transcript and
  transcribe from `time` if not covered, saving after each chunk (debounced ~2 s and on `stop`).
  A run that stops because the next segment isn't on the device leaves the state `.ready` until the
  shown time passes the covered end, then `.needsDownload`.

- [ ] **Step 1: Failing tests** (all with `StubReadAlongTranscriber` and a temp `ReadAlongStore`):
  - `show` on an uncovered time → `.preparing`, then `.ready` with lines; transcription started at
    that time (`transcribeStarts == [time]`).
  - A saved transcript covering the time → `.ready` immediately, no transcribe call.
  - **(Review Focus 2)** `timeChanged` from 100 to 2000 while a run is in progress → the old run is
    cancelled and a new one starts at 2000 (`transcribeStarts == [100, 2000]`); a small move (100 →
    103) inside the run's reach starts nothing.
  - **(Review Focus 1)** `show(bookB, …)` after `show(bookA, …)` → A's run cancelled, A's transcript
    saved under A, the session's transcript is B's (never A's lines).
  - Stored language `"en"` with supported `["en-US","pt-BR"]` → uses `"en-US"` and saves it.
  - No stored language, installed `["en-US","pt-BR"]`, stub confidences en 0.4 / pt 0.9 → `"pt-BR"`
    chosen and saved; all below 0.5 → the in-app language's locale.
  - Model `downloadable` → `.downloadingModel("pt-BR")`, `installModel` called once, then `.ready`.
  - `unsupported` → `.unsupported(locale)` and no transcribe call.
  - LibriVox chapter not downloaded → `.needsDownload`, no transcribe call. **(Review Focus 5)**
    the file then appears and `downloadsChanged` is called → `.preparing` → `.ready`.
  - Imported file missing → `.fileMissing`.
  - `setLanguage("pt-BR")` → setting saved, store's transcript for the book deleted, a new run.
  - **(Review Focus 4)** `stop()` during a run with a slow stub → no further `save` after the store's
    `deleteAll()` (the run checks cancellation before each save).
- [ ] **Step 2: Run, expect FAIL**
- [ ] **Step 3: Implement** the session with one `Task` for the current run, cancelled on
  retarget/stop; `ReadAlongCenter` in the container (`ReadAlongCenter(transcriber: DebugOverrides.readAlongTranscriber() ?? live-if-iOS-26, store: .shared, settings:)`);
  the container's `clearReadAlong` path also stops the live session. Add `-seedReadAlong` to
  `LaunchArgument` (doc comment: *stub transcriber with canned lines for every book, and Read-along
  on; use with `-resetSettings`*) and to `LaunchArgument.all`; under it `DebugOverrides` turns
  `readAlongEnabled` on in the in-memory settings.
- [ ] **Step 4: Run, expect PASS**
- [ ] **Step 5: Commit** `feat(read-along): session that transcribes only while shown (#192)`

---

### Task 7: Settings › Experimental

**Files:**
- Modify: `Abbay/View/Settings/SettingsView.swift` (new `experimentalSection`, after `languageSection`)
- Modify: `Abbay/Core/AccessibilityID.swift` (`Settings.readAlong = "settings.experimental.readAlong"`)
- Modify: `Abbay/Resources/Localizable/Localizable.swift`, `Localizable.xcstrings`
- Test: `AbbayUITests/SettingsUITests.swift`

**Copy (en / pt-BR):**
| key | en | pt-BR |
|---|---|---|
| `experimentalTitle` | Experimental | Experimental |
| `readAlongToggle` | Read-along | Leitura acompanhada |
| `readAlongFooter` | Shows the audiobook's text as it plays, highlighting the words being read. The text is made from the audio on this iPhone, so it can get words wrong, especially names. Nothing is sent anywhere and the microphone is never used. The first time a language is used, iOS may download its speech model. | Mostra o texto do audiolivro enquanto ele toca, destacando as palavras lidas. O texto é gerado a partir do áudio neste iPhone, então pode errar palavras, principalmente nomes. Nada é enviado e o microfone nunca é usado. Na primeira vez que um idioma é usado, o iOS pode baixar o modelo de fala dele. |

- [ ] **Step 1: Failing UI tests** (`-resetSettings`, skipped below iOS 26):
  `test_experimental_readAlong_offByDefault` (switch `settings.experimental.readAlong` exists, value
  `"0"`); `test_experimental_readAlong_toggles` (tap → `"1"`, tap → `"0"`);
  `test_experimental_footerExplains` (footer text contains "microphone"; pt-BR run contains
  "microfone"). Persistence is proven by Task 3's unit test. Add the id to
  `AccessibilityIdentifierTests` if that suite enumerates Settings ids.
- [ ] **Step 2: Run, expect FAIL**
- [ ] **Step 3: Implement** `experimentalSection` inside `if #available(iOS 26, *)`, a `Toggle`
  bound to `settings.readAlongEnabled`, footer text, and the strings.
- [ ] **Step 4: Run, expect PASS**; existing `test_gear_opensSettings_withEverySection_andDoneCloses`
  still passes (update its section list for iOS 26+).
- [ ] **Step 5: Commit** `feat(read-along): Settings › Experimental switch (#192)`

---

### Task 8: The player: Text pill and the read-along square

**Files:**
- Create: `Abbay/View/PlayerView/ReadAlongView.swift`
- Modify: `Abbay/View/PlayerView/PlayerView.swift` (pill, square swap, shared scrub)
- Modify: `Abbay/View/PlayerView/PlayerViewModel.swift` (`liveBookTime()`)
- Modify: `Abbay/Core/AccessibilityID.swift`, `Localizable.swift`, `Localizable.xcstrings`
- Test: `AbbayTests/PlayerViewModelTests.swift` (or the existing VM test file), `AbbayUITests/ReadAlongUITests.swift`

**Interfaces:**
- Consumes: `ReadAlongCenter`/`ReadAlongSession`/`ReadAlongState` (Task 6), `AppSettings.readAlongEnabled`/
  `readAlongShowsText` (Task 3), `ReadAlongLanguage.displayName` (Task 2).
- Produces:
  ```swift
  // PlayerViewModel
  func liveBookTime() -> Double           // loaded: player.currentTime if finite, else book.currentTime
  // PlayerView.swift: `Scrub` becomes internal `PlayerScrub`, owned by PlayerView (@State) and passed
  // to PlayerTimeline and ReadAlongView, so the text follows the scrubber while dragging.
  struct ReadAlongView: View { init(model: PlayerViewModel, scrub: PlayerScrub) }
  // AccessibilityID.Player
  static let text = "player.text"                    // the pill
  static let readAlong = "player.readAlong"          // the square
  static let readAlongLanguage = "player.readAlong.language"
  static let readAlongStatus = "player.readAlong.status"
  static func readAlongLine(_ i: Int) -> String { "player.readAlong.line.\(i)" }
  ```

**Behaviour to build (from the spec, *The player: option A*):**
- Pill row: speed · **Text** · Chapters, Text only when `center.isAvailable && settings.readAlongEnabled`.
  Label *Text* / *Texto* with `text.quote`; while the text shows, `photo` icon and VoiceOver label
  *Show cover* / *Mostrar capa*. Tap toggles `settings.readAlongShowsText`.
- `coverView` shows `ReadAlongView` in the same square (same frame, radius `coverRadius`, the
  `FrameReporter` stays on the square so the expansion still lands there) when the pill is on.
- `ReadAlongView`: `TimelineView(.periodic(from: .now, by: 0.1))` while on screen; time =
  `scrub.time ?? model.liveBookTime()`; calls `session.show(book, at:)` on appear and when
  `model.book.url` changes, `timeChanged` on each tick, `downloadsChanged` on
  `model.downloadEntry` changes, `stop()` on disappear and on `scenePhase != .active`.
- Lines in a `ScrollView` + `ScrollViewReader`, current line centred; current line white semibold,
  current word `ColorConstants.malachite`, past lines 35% white, upcoming 55%; top/bottom fade mask.
  `@ReduceMotion`: scroll without animation and no word highlight.
- Tap a line → `model.seek(line.start)` (does nothing when the shown book isn't loaded).
- Language label (`Menu`, bottom-leading glass capsule, *English ▾*): lists `session.choices` by
  `displayName`; selection → `session.setLanguage`. VoiceOver label *Text language* / *Idioma do texto*.
- Status overlay for non-`.ready` states (id `readAlongStatus`), copy below. Lines are plain
  accessible static text; no announcements on highlight changes.

**Copy (en / pt-BR):**
| key | en | pt-BR |
|---|---|---|
| `readAlongPill` | Text | Texto |
| `readAlongShowCover` | Show cover | Mostrar capa |
| `readAlongPreparing` | Preparing text… | Preparando o texto… |
| `readAlongDownloadingModel` | Downloading the %@ speech model… | Baixando o modelo de fala em %@… |
| `readAlongUnsupported` | Text isn't available in %@. | Texto não disponível em %@. |
| `readAlongNeedsDownload` | The audio must be downloaded first to show its text. | O áudio precisa ser baixado primeiro para mostrar o texto. |
| `readAlongFileMissing` | The audio file must be on this iPhone to show its text. | O arquivo de áudio precisa estar neste iPhone para mostrar o texto. |
| `readAlongNoSpeech` | No speech here. | Sem fala neste trecho. |
| `readAlongFailed` | Couldn't make the text. | Não foi possível gerar o texto. |
| `readAlongLanguage` | Text language | Idioma do texto |

(`readAlongNoSpeech` shows when the state is `.ready` but `position(at:)` is nil.)

- [ ] **Step 1: Failing unit test** — `liveBookTime()` returns the mock player's `currentTime` for
  the loaded book and `book.currentTime` for another book.
- [ ] **Step 2: Failing UI tests** in `ReadAlongUITests` (launch `-seedLibrary -seedPlayableBook
  -resetSettings` + `-seedReadAlong` unless noted; skip with `XCTSkip` below iOS 26):
  - `test_pill_absentWhenReadAlongOff` (no `-seedReadAlong`): `player.text` doesn't exist.
  - `test_pill_flipsCoverToText_andBack`: tap `player.text` → `player.readAlong` exists and
    `player.readAlong.line.0` exists; tap again → `player.readAlong` gone.
  - `test_text_followsPlayback`: play, wait until the line with "Seeded line" whose index > 0 is
    selected (`isSelected` trait on the current line), pause.
  - **(Review Focus 3)** `test_lineTap_onABookNotLoaded_doesNotStartPlayback`: open the playable
    book without playing, show text, tap a line → transport still *Play*.
  - `test_lineTap_onLoadedBook_seeks`: play, tap `line.5` → the scrubber's elapsed label moves to ~20 s.
  - `test_languageMenu_listsLanguages`: tap `player.readAlong.language` → a menu with *English*.
  - `test_reduceMotion_stillShowsCurrentLine` (`-forceReduceMotion`).
  - `test_textStaysUp_acrossReopen`: show text, close player, reopen → `player.readAlong` exists.
  - `test_landscape_textTakesTheCoversPlace`: show text, `XCUIDevice.shared.orientation = .landscapeLeft`
    → `player.readAlong` still exists and its frame's minX < the transport's minX (leading side).
- [ ] **Step 3: Run, expect FAIL**
- [ ] **Step 4: Implement** per *Behaviour to build*.
- [ ] **Step 5: Run the new tests and the existing player suites** (`MiniPlayerUITests`,
  `ChaptersPanelUITests`, `AdaptiveLayoutUITests`, `CoverUITests`): PASS. The pill row with
  Read-along off must be pixel-identical to today (compare the *before* screenshot).
- [ ] **Step 6: Commit** `feat(read-along): Text pill and the read-along square on the player (#192)`

---

### Task 9: Docs, live verification, and the PR

**Files:**
- Create: `.claude/skills/verify-abbay/features/read-along.md` (sub-features, ids, launch args,
  expected evidence, following the other pages' format)
- Modify: `.claude/skills/verify-abbay/features/player.md` (Text pill, the square), `settings.md`
  (Experimental), and the map's index if it lists pages
- Modify: `docs/superpowers/specs/2026-10-29-read-along-design.md` only if something built differs

- [ ] **Step 1: Write the feature-map pages.** Each id and launch argument from Tasks 6–8 appears.
- [ ] **Step 2: Privacy check.** Confirm no new host (grep for URLs added in the diff) and that
  `PrivacyInfo.xcprivacy` needs no entry for Speech; note the result for the PR.
- [ ] **Step 3: Gate.** `bundle exec fastlane verify` → SwiftLint strict clean, unit and UI suites
  pass. Record the exact test counts.
- [ ] **Step 4: Live in the Simulator** (iOS 26+ runtime): drive `read-along.md` with
  `-seedReadAlong`, and without it on the playable book to see whether the real engine runs there.
- [ ] **Step 5: Screenshots** (same simulator, seed, `-seedArtwork`): *before* from `develop` (the
  player, Settings), *after* from the branch (player with text, Settings › Experimental), en and
  pt-BR. Commit them to the orphan `pr-screenshots` branch under `pr-<n>/` once the PR number exists.
- [ ] **Step 6: OTA build for the owner's iPhone 15** (`.superpowers/ota/`, see the
  remote-install notes), `Scripts/check-app-binary --allow-debug-resources` first. The owner tests
  with a LibriVox book and an imported book (e.g. their full-cast m4b), in English and Portuguese.
- [ ] **Step 7: File gaps as issues** before the PR merges (`gh issue list` first): at least any
  Simulator limitation found in Task 5, and anything the owner's device test turns up. Comment on
  #192 with the new approach (speech recognition only, iOS 26+, no ebooks).
- [ ] **Step 8: When the owner asks**, push and open the PR into `develop`: what shipped, tests
  (exact counts), feature-map pages updated and what was driven, screenshots, known gaps (linked
  issues), what's next. No AI attribution. Do not merge until the owner has tested the OTA build.
