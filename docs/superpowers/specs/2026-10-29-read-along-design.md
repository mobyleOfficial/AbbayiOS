# Read-along (experimental): design

Issue: #192. Date: 2026-10-29. Status: draft for Edson's review.

This replaces the approach written in #192. The issue planned to show existing text (Project
Gutenberg for LibriVox books, a user-attached EPUB for imported ones) and leave speech recognition
for a later v2. After talking it through, the owner chose **speech recognition only, from the
start**: the text comes from the audiobook's own audio, on the device, for every book. No ebook or
text is downloaded from anywhere and nothing is attached. Record that change on #192 when the work
starts.

## Intent

A listener who is mostly listening, by ear, glances at the screen when a word catches them,
often to learn how it is written or pronounced (the issue's case: practising English with
audiobooks). The owner's picture is **karaoke**: the text on screen marks what is being said right
now, and it should be **close to what we're hearing**, not an estimate that drifts.

It is experimental and opt-in. When it is off, the app is exactly today's app.

## Goals

- While a book plays, the player can show the text being read, with the line being read and the
  word being spoken highlighted, tracking the audio closely.
- It works the same for **LibriVox books and imported files**. Imported books matter to the owner.
- Everything happens on the device. Nothing leaves it; no new network host.
- Fast enough that showing the text feels immediate (owner's bar: about 5 s at most; measured:
  under half a second, see *Spike results*).

## Non-goals

- Downloading ebooks or text from anywhere (Gutenberg, archive.org text, etc.).
- Attaching EPUB or text files to imported books.
- Editing, searching, copying out, translating or exporting the text.
- Read-along on the mini player, lock screen, Now Playing, CarPlay or Siri.
- Support below iOS 26.

## Anti-goals (would be a failure even if it works)

- Anything running, transcribing or downloading while the feature is off.
- Any use of the microphone, or any permission prompt.
- Uploading audio or text anywhere.
- Draining battery while the user is only listening (nothing runs while the text isn't on screen).
- The player looking or behaving any differently for users who haven't turned it on.

## Constraints

- **iOS 26 and newer only** (owner decision). Apple's long-form `SpeechAnalyzer` /
  `SpeechTranscriber` API is iOS 26+. Gate everything with `@available(iOS 26, *)`; the
  deployment target stays **iOS 17.0** (project rule). On iOS 17–25 the feature does not exist:
  no Settings section, no pill, no code path runs.
- No `NSSpeechRecognitionUsageDescription` or `NSMicrophoneUsageDescription`. The spike shows file
  transcription with `SpeechTranscriber` works with authorization never requested (see below).
  If that ever stops being true, stop and come back to the owner; do not add a prompt.
- Every user-visible string in `Localizable.xcstrings`, `en` and `pt-BR`.
- Project rules in `CLAUDE.md` apply: feature map page, live verification, before/after
  screenshots (en and pt-BR), gaps filed as issues, `bundle exec fastlane verify`.

## Spike results (2026-10-29)

Throwaway test, not kept. `SpeechTranscriber(locale: en_US, reportingOptions: [.volatileResults],
attributeOptions: [.audioTimeRange])` + `SpeechAnalyzer.analyzeSequence(from: AVAudioFile)`, on
the owner's *Harry Potter and the Philosopher's Stone (Full-Cast Edition)* chapter 1 (31:47, music,
sound effects, several voices: a hard case), on the owner's iPhone 15, iOS 27.2, in the foreground:

| | iPhone 15 |
|---|---|
| first finished sentence, from the chapter start | 0.14 s |
| first finished sentence, from a 3-min slice taken mid-chapter | 0.45 s |
| whole chapter | 27.4 s (≈ 70× real time) |
| lead over playback | always ahead, at 1× and at 2× |
| timed words | 4,532, each with an `audioTimeRange` |
| speech authorization | `.notDetermined` before and after; no Info.plist key present |
| thermal state | nominal throughout |
| English model | already installed (en_US and eight other English locales) |

A Mac (macOS 27) gave the same numbers. Accuracy is high on narration. Errors cluster on character
voices and proper nouns ("Dundee" → "Dee", "rain" → "raid", "sleeping pattern" → "sleeping
better", "the Potters" lowercase), and a few short in-character lines were dropped.

Not measured: a first-time language model download; transcription while audio plays at the same
time; behaviour in the background (not needed, see *When transcription runs*).

## What the user sees

### Settings › Experimental

A new **Experimental** section in `SettingsView`, shown only on iOS 26+.

- One switch, **Read-along**, off by default, persisted in `AppSettings` like the other settings.
- A footer explaining it: the app writes the text from the audiobook's audio, on this iPhone; it
  can get words wrong, especially names; nothing is sent anywhere and the microphone is never used.
  Exact wording is the builder's, in both languages.
- Turning it **off** hides the Text pill and deletes all saved transcripts, so "off" leaves nothing
  behind. *(My call; the owner agreed with the summary.)*

### The player: option A, the text swaps with the cover

The owner picked this from three mockups ("A is the best by far"): the text takes the **cover's
square**, like lyrics in Apple Music. Everything else on the player stays where it is.

- **A Text pill** between the speed pill and the Chapters pill, only when Read-along is on (and
  iOS 26+). Tapping it flips the cover square to the text; tapping again flips back. With the
  feature off, the pill row is exactly today's.
- *My call:* whether the text or the cover is showing is remembered app-wide, so it stays up across
  books and launches until flipped back.
- **In the square:** about three lines. The current line bright white and semibold; the word being
  spoken in the app's green (malachite); lines already read faded; upcoming lines dimmer. The
  current line is kept centred and the text scrolls smoothly. Top and bottom edges fade out.
- **Reduce Motion:** no smooth scrolling (the text jumps line to line) and no per-word highlight,
  only the current line.
- **Tap a line** to seek the audio to its start (handy to re-hear a word). *(My call; the owner
  didn't object.)*
- **Paused or scrubbing:** the text follows the shown position, including the scrubber while
  dragging, so the user sees where they will land.
- **Landscape, iPad and the split-window pane** (`PlayerView` layouts from #270/#255): the text
  takes the cover's place in each.
- **VoiceOver:** the text is readable as ordinary static lines; nothing is announced as the
  highlight moves (it would talk over the narrator). **Dynamic Type:** the text scales; fewer lines
  fit in the square, the current one stays centred.
- **States the square must show** (each with a short message, en and pt-BR):
  - *Preparing text…* while the first lines are transcribed (expected under a second);
  - *Downloading the <language> speech model…* the first time a language is needed;
  - *Text isn't available in <language>* when iOS can't transcribe that language (the language
    label still lets the user pick another);
  - before speech (an intro, a pause over 5 s) the next line shown dimmed, lighting up when the
    narrator reaches it; a ♪ (VoiceOver *No speech here*) when the next line is over 30 s away or
    there is none (owner decision after the first device test: *No speech here.* during a
    full-cast intro read as broken);
  - *The audio must be downloaded first* when the part being played isn't on the device (a
    LibriVox chapter that is streaming, an imported file iCloud has offloaded). See *Audio that
    isn't on the device*.

### Language

- **LibriVox books** use the language LibriVox lists (`LibriVoxBook.language`, an ISO 639-2 code
  such as `eng`). It is not carried into `AudioModel` or Core Data today, so store it when a book is
  added. *(My call:)* LibriVox books already in the library, which have no stored language, are
  treated like imported books and detected; no re-fetch, no migration.
- **Imported books:** detected the first time the text is shown. iOS's speech API has no language
  identification, so the app does its own: transcribe a short sample (tens of seconds, from the
  current position) with each candidate locale (the app's language, the device's preferred
  languages, and English, limited to locales whose model is **already installed**, so detection
  never downloads a model just to score it *(my call)*) and keep the one with
  the best recognition confidence. The exact scoring is the builder's; verify it on real
  Portuguese audio (a pt LibriVox book) and real English audio. If it isn't reliable, fall back to
  the app's language and rely on the picker.
- **Changing it:** a small language label in a corner of the text square (*English ▾*). Tapping it
  lists the languages iOS can transcribe. The choice is saved per book, LibriVox books included.
  Changing it discards that book's saved transcript and transcribes again.

## How it works

### When transcription runs

On demand only: **while the text is showing**, from the current position, ahead of playback,
saving what it finishes. When the text is hidden, or the player closes, or the app goes to the
background, transcription stops. At ≈ 70× real time there is no need to prepare text ahead or in
the background. A seek to a part not yet transcribed restarts transcription from there.

How far ahead to run while visible (to the end of the chapter, a fixed window, or on to the end of
the book) is the builder's call; keep it cheap and keep the current line always covered.

### The pieces

- **A transcript source behind a protocol** (the issue's testability requirement), e.g.
  `ReadAlongTranscribing`: given a book, a language and a book-time position, produce timed
  segments (sentences or phrases) with timed words. The real one wraps `SpeechAnalyzer`; a stub
  serves canned transcripts for unit and UI tests.
- **Timing in book time.** Everything outside the player speaks book time (`BookTimeline`,
  `PlaybackClock.bookTime`). A transcript is stored as book-time ranges with their words, so the
  view only needs the current book time to know what to highlight.
- **Reading the audio.** LibriVox books are one file per chapter (`MultiFileQueue`,
  `LibriVoxIdentity.localFileURL(for:bookID:)`); imported books are one file, possibly with chapter
  markers, opened through the security-scoped bookmark (`AudioModel.fileURL`, `bookmarkData`).
  Seek into the file (`AVAudioFile.framePosition`) to start mid-chapter.
- **Storage.** Saved transcripts are files on disk keyed by the book's identity (`AudioModel.url`,
  which doesn't change when the file moves) and language: for LibriVox books inside the book's
  directory (`LibriVoxIdentity.directory(forBookID:)`), for imported books in an app-owned folder.
  They are deleted with the book (the same delete path as today), when the language changes, and
  when the feature is turned off. They must not be included in backups in a way that breaks the
  privacy story; the builder decides the exact location.
- **Model assets** via `AssetInventory.assetInstallationRequest(supporting:)`. iOS downloads Apple's
  speech model for a language once; it is shared system-wide. *(My call:)* the download starts only
  as a result of the user showing the text (or picking a language) for a book whose language model
  isn't installed, with the *Downloading…* state, and no extra confirmation: it is the system's
  download from Apple, not the app's, and not book data. Mention it in the footer if the wording
  allows.
- **A faster clock while visible.** `PlaybackClock` ticks once a second (`Player.swift`), too
  coarse for a per-word highlight. Add a finer time source (e.g. a periodic time observer or a
  `TimelineView` reading the player's current time) that runs **only while the text is showing**.

### Audio that isn't on the device

Owner decision: **wait for the download, and say so.** Transcription only reads files on the device;
it never streams audio, fetches it separately, or starts a download on its own.

- A LibriVox chapter that isn't downloaded: the square shows a warning that the audio must be
  downloaded first. If the book is already downloading, the text appears by itself as soon as the
  current chapter's file is on the device. The user downloads the usual way (the existing Download
  button and its cellular rules); read-along adds no download path.
- An imported file that isn't on the device (iCloud offloaded, or a lost bookmark): the same kind of
  warning, saying the file must be on this iPhone.

### Testability

- A Debug launch argument (in `LaunchArgument.swift`) seeds a canned transcript for the seeded
  books, so UI tests and screenshots run without real recognition, plus a way to turn the setting on
  at launch. Names are the builder's.
- New accessibility ids in `AccessibilityID.swift`: at least the Text pill, the text square, the
  language label, and the Settings switch.
- Unit tests: highlight lookup from a book time (line and word), storage keyed and deleted
  correctly, the off switch deleting transcripts, language choice persistence, detection scoring on
  a stubbed recognizer.
- UI tests: the switch off by default; pill absent when off; pill flips cover ↔ text; the seeded
  text highlights and follows playback; tapping a line seeks; the language picker; Reduce Motion.

## Docs, privacy and housekeeping

- **Feature map:** a new page `.claude/skills/verify-abbay/features/read-along.md`, and updates to
  `player.md` (the Text pill, the square) and `settings.md` (Experimental).
- **Privacy:** no new host and no data leaving the device, so the privacy policy and the
  networking allowlist (#188) don't change. Check the policy's wording still holds, and check
  whether the privacy manifest needs anything for the Speech framework (it is not a
  required-reason API as of writing).
- **#192:** comment with the new approach (speech recognition only, iOS 26+, no ebooks) so the
  issue matches what ships.
- **Screenshots:** before (develop) and after, en and pt-BR, the player with text showing.

## Left to the builder

Named above where they arise: the transcript file format and folder; the protocol's exact shape;
how far ahead to transcribe; language-detection scoring; launch-argument and accessibility-id
names; exact copy (both languages); the highlight animation within the Reduce Motion rule.

## Testing and shipping

Owner's view: this is an experimental feature, so keep the proof proportionate.

- **Manual tests on the owner's iPhone** are the real check: the speech engine may not run in the
  Simulator, and transcribing while audio plays wasn't measured by the spike. The PR **does not
  merge until the owner has tested an over-the-air build** (the same checkpoint as #166) and said so.
- **Automated tests where they come cheaply:** unit tests for the pure parts (highlight lookup,
  storage, settings, detection scoring against a stub) and UI tests through the stub transcript and
  launch argument. Check early whether `SpeechTranscriber` works in the Simulator; if it does, a
  small real-recognition test on public-domain LibriVox audio is a bonus, not a requirement.
- *(My call:)* it ships in release builds like any other feature, off by default behind the
  Experimental switch. The owner can hold it back at release time.
