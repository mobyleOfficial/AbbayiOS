# Read-along (experimental)

Read-along (#192) shows the text of the audiobook being played, made **on the device from the book's
own audio** (Apple's `SpeechTranscriber` / `SpeechAnalyzer`, iOS 26 and later), in the
[player](player.md)'s cover square, with the line being read and the word being spoken marked. It is
opt-in: a switch in [Settings](settings.md) › Experimental, off by default. With it off the app is
exactly the app without it. Nothing is downloaded from anywhere, no ebook is attached, the
microphone is never used and no speech-recognition permission is asked: the transcriber reads files
that are already on the iPhone.

The pieces: `AppSettings.readAlongEnabled` (the switch); `ReadAlongCenter` (is it available, and the
one place that makes a session or a transcript store); `ReadAlongSession` (what runs while the text
shows: audio, language, transcription, saving); `SpeechReadAlongTranscriber` (the real engine
behind the `ReadAlongTranscribing` protocol); `ReadAlongStore` (saved transcripts, JSON files);
`ReadAlongView` (the square); `PlayerView`'s Text pill.

## Sub-features

- **switch** (`settings.experimental.readAlong`): Settings › Experimental › *Read-along* (pt-BR
  *Leitura acompanhada*), iOS 26+ only, and only where Speech's transcriber runs
  (`SpeechTranscriber.isAvailable`). Off by default; the footer says the text is made on the
  device, can be wrong, nothing is sent and the microphone is never used. On iOS 17 to 25, in the
  Simulator and on hardware without the engine the section is not drawn, the pill does not exist
  and no read-along code runs (`ReadAlongCenter.isAvailable` is false: the container makes no
  transcriber). Details in [settings](settings.md).
- **off leaves nothing:** switching it off stops a running session and deletes every saved
  transcript (`ReadAlongStore.deleteAll`); the Text pill goes away. A book deleted from the library
  loses its transcript too (`DeleteAudioUseCase`).
- **text pill** (`player.text`): between the speed and Chapters pills, only with Read-along on.
  Flips the cover's square to the text and back; VoiceOver reads *Text* / *Show cover*. Whether
  the text shows is remembered app-wide. See [player](player.md) *read-along*.
- **the square** (`player.readAlong`): the cover's frame, dark fill, the lines scrolling with the
  current one centred (white, semibold, the spoken word in malachite; read lines faded, upcoming
  ones dimmer). Lines are `player.readAlong.line.<n>`, buttons to VoiceOver with the hint *Plays
  from this line* / *Toca a partir desta linha*; the current one has the selected trait. It
  follows playback every 0.1 s, the saved position for a book that isn't loaded, and the scrubber
  while dragging (showing covered text only; transcription starts where the finger lifts). **Reduce Motion:** the text jumps line to line, no word highlight.
- **tap a line:** seeks the loaded book to the line's start. On a book that isn't loaded it does
  nothing (it never loads or plays a book).
- **language:** a LibriVox book uses the language LibriVox lists (stored when the book is added); an
  imported book, and a LibriVox book added before this, is detected the first time the text shows:
  a short sample is scored with each candidate language whose speech model is **already installed**
  (the app's language, the device's, English), and the best recognition confidence wins; if nothing
  is decisive the in-app language is used. A bare language ("eng" → "en") takes the device's
  region for it, else a region whose model is already installed, else the language's likely one
  (en-US, pt-BR, es-ES), never the alphabetically first (en-AU). The label (`player.readAlong.language`, *English ▾*)
  opens a menu of the languages iOS can transcribe; picking one is saved for the book, deletes its
  transcript and transcribes again.
- **messages** (`player.readAlong.status`): *Preparing text…*, *Downloading the English speech
  model…* (iOS fetches Apple's model once per language, only because the text was shown),
  *Text isn't available in X.*, *The audio must be downloaded first to show its text.* (a LibriVox
  chapter not on the device; the text appears by itself when it finishes), *The audio file must be
  on this iPhone to show its text.* (an imported file that is not), *No speech here.*, *Couldn't
  make the text.* Read-along never streams audio and starts no download of its own.
- **only while shown:** the session runs only while the square is on screen. It stops when the pill
  flips back, the player closes or the screen follows nothing, Read-along is turned off, or the app
  leaves the foreground, and it picks up again when the text shows. A seek past the covered text
  restarts transcription from there; it works ahead of playback (about 70 times real time on an
  iPhone 15) but only ten minutes past the shown time (`ReadAlongSession.runAhead`), starting the
  next stretch when playback is within a minute of the end (`lookahead`). It saves what it
  finishes off the main thread; a book deleted while its text shows is not written back.
- **stub engine** (`-stubReadAlongEngine`, Debug only): swaps the engine for
  `StubReadAlongTranscriber` with its own transcript store, leaving Read-along as the settings have
  it (off under `-resetSettings`): Settings' Experimental section is drawn in the Simulator.
  `-seedReadAlong` implies it and also turns Read-along on in the in-memory settings that
  `-resetSettings` gives. The stub is `StubReadAlongTranscriber` (a line every 4 s of book
  time, "Seeded line N of the read-along text", words 0.5 s apart; English and Portuguese offered)
  and keeps its transcripts in a store of its own in the temporary directory, emptied at launch. No
  speech model, no iOS 26 engine and no real recognition is needed, so the same text appears on the
  Simulator.

## How to get to it (user POV)

1. Settings (the Library's gear) › Experimental › switch Read-along on (iOS 26+).
2. Open a book's player; tap **Text** between the speed and Chapters pills.
3. Tap **Show cover** (the same pill) to go back.

## Driving it with abbay-ctl

```bash
$B launch -seedLibrary -seedPlayableBook -seedArtwork -resetSettings -seedReadAlong
$B tap library.toolbar.settings && $B wait settings.experimental.readAlong      # value "1" under -seedReadAlong; tap it to switch off (transcripts deleted)
$B tap library.row.<n>.title && $B wait player.close     # find "Seeded Playable Book" by title
$B tap player.text && $B wait player.readAlong.line.0    # the square replaces the cover
$B tap player.transport.play && $B snapshot              # the selected line moves on, a line every 4 s
$B tap player.readAlong.line.5                           # seeks to its start (loaded book)
$B tap player.readAlong.language                         # menu: English (checked), Portuguese
$B tap player.text                                       # back to the cover; the square is gone
$B launch -seedLibrary -seedPlayableBook -seedArtwork -resetSettings -forceReduceMotion -seedReadAlong
                                                         # one selected line, jumping, no word colour
$B launch -seedLibrary -seedPlayableBook -resetSettings  # Read-along off: no player.text anywhere
```

Without `-seedReadAlong`, turning the switch on (Settings) drives the **real engine**: on a device
the first lines appear in about half a second. In the iOS Simulator the engine is not available
(see Gotchas).

**Verified** (`ReadAlongUITests`, `SettingsUITests.test_experimental_*` under
`-stubReadAlongEngine`; skipped below iOS 26):
- Without an engine (the Simulator, no stub) Settings draws no Experimental section.
- Read-along off by default (`-resetSettings`): no `player.text`; the switch toggles and its footer
  names the microphone (en and pt-BR).
- `player.text` flips to `player.readAlong` with `player.readAlong.line.0`, and back; lines are
  buttons.
- The selected line moves on while playing; with `-forceReduceMotion` exactly one line is selected.
- A line tap on a book that isn't loaded leaves *Play* showing; on the loaded book it moves the
  elapsed time to the line's start.
- `player.readAlong.language` opens a menu with *English* and *Portuguese*; the label's value is
  *English*.
- The text stays up after closing and reopening the player; flipping off and on, and rotating,
  bring the text straight back (one session per screen).
- In landscape the square sits on the leading side, clear of the transport.
- Unit: highlight lookup, the store (keyed, deleted), the settings, language mapping and detection
  pick and region choice, the session (nothing runs while hidden, cancellation, saving, retarget,
  the ten-minute window, no run while scrubbing, a deleted book stays deleted), the store (saves
  queued, stamps), the detection sample's length and format, the line hint, the audio source
  (book time to files on the device), the transcriber's segmentation, `liveBookTime`, the menu's
  naming.

**Not driven by a UI test:** the status messages other than the stub's quick *Preparing text…*, the
scene-phase stop, a real LibriVox download finishing under the square, VoiceOver, iPad and the split
pane (same cover path), and the **real engine**: its tests skip in the Simulator, so its proof is a
macOS 27 harness run and the owner's device test.

## Gotchas

- **The real engine does not run in the iOS Simulator.** `SpeechTranscriber` reports itself
  unavailable there, so the engine tests in `SpeechReadAlongTranscriberTests` skip, and without a
  stub the app treats the feature as unavailable: no Experimental section, no Text pill. Use
  `-stubReadAlongEngine` for Settings and `-seedReadAlong` for the player; use a device for the
  engine.
- **English against Portuguese detection has never run for real** (no Portuguese speech model was
  available to the builder): the scoring is unit-tested against a stub only. Check it on a
  Portuguese LibriVox book and an English one, on a device.
- **iOS 17 to 25 has no Read-along, except under `-seedReadAlong` / `-stubReadAlongEngine`.**
  Without them, an iOS 17.5 simulator shows no Experimental section in Settings and no Text pill
  (driven in task 9). With them, the Debug stub counts as an engine, so the pill appears there: an
  artefact of the launch arguments, which Release builds don't have. Verify the absence without
  them.
- **The playable seed is saved 200 s in**, so with the stub its first line is line 51 (3:20); line
  ids are positions in the transcript and shift when an earlier run inserts lines.
- **The text square takes drags:** while it shows, the cover's collapse handle stands aside
  ([mini-player](mini-player.md)); close with the header or ⌄.
- **It makes sound:** the playable seed plays real audio; pause it.
- **The Text pill needs the switch on first** (or `-seedReadAlong`); `-resetSettings` alone has it
  off.
