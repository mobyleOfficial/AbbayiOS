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
`ReadAlongView` (the square); `ReadAlongFullScreenView` (the same text over the whole window);
`PlayerView`'s Text pill.

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
  Flips the cover's square to the text and back; the pill reads *Text* / *Texto* over the cover and *Cover* / *Capa* over the text; VoiceOver reads *Text* / *Show cover*. Whether
  the text shows is remembered app-wide. See [player](player.md) *read-along*.
- **the square** (`player.readAlong`): the cover's frame, dark fill, the lines scrolling with the
  current one centred (white, semibold, the spoken word in malachite; read lines faded, upcoming
  ones dimmer). Lines are `player.readAlong.line.<n>`, buttons to VoiceOver with the hint *Plays
  from this line* / *Toca a partir desta linha*; the current one has the selected trait. A line
  stays current through a pause of up to 5 s after it ends. **Before speech** (an intro, a longer
  pause) the next line waits in the middle, dimmed, nothing highlighted, and lights up in place
  when the narrator reaches it; when the next line is more than 30 s away, or there is none, the
  square shows a ♪ (`music.note`, VoiceOver *No speech here*) instead (owner decision, after a
  full-cast intro showed *No speech here.* until the narrator started). Rules in
  `ReadAlongTranscript.display(at:)`. It
  follows playback every 0.1 s, the saved position for a book that isn't loaded, and the scrubber
  while dragging (showing covered text only; transcription starts where the finger lifts). **Reduce Motion:** the text jumps line to line, no word highlight.
- **full screen** (owner's follow-up after the device test): the square's **expand** button
  (`player.readAlong.expand`, bottom-right, opposite the language label, a glass circle with
  `arrow.up.left.and.arrow.down.right`; VoiceOver *Full screen* / *Tela cheia*) shows the same text
  over the **whole window** (`player.readAlong.fullScreen`): above the tabs, the mini player and the
  player on an iPhone, and over **both panes** on the iPhone Duo and a split iPad. Drawn by the root
  (`ReadAlongFullScreenHost` in `AppRootView`) from `PlayerPresentation.readAlongFullScreen`. The
  player's cover-tint gradient behind it (reaching every edge; the status bar stays), the lines
  larger (`.title`) in a centred column at most 600 pt wide, the current line in the middle, the
  same highlight rules, a line tap still seeks. Along the bottom: the language label (left),
  **play/pause** (`player.readAlong.playPause`, centre, *Play* / *Pause*) and **collapse**
  (`player.readAlong.collapse`, right, `arrow.down.right.and.arrow.up.left`, *Exit full screen* /
  *Sair da tela cheia*). No skips (owner's call). VoiceOver's escape collapses it too. It shows the
  **same session** as the square (the screen's `ReadAlongSessionSlot`, which counts it as on screen),
  so nothing is prepared again on the way in or out. It ends when the player closes, another book is
  presented, the screen follows another loaded book (never book A's text over book B), the pill
  flips back or Read-along goes off, and on a change of split (a fold, a resize: the other layout's
  player has a session of its own; collapse there and expand again). Not remembered: the player
  always opens with the square. Scale and fade in and out; a plain fade with Reduce Motion. While
  the chapter panel is open the expand button is left out of the hierarchy, like the language label
  (a glass button faded by its parent still drew over the panel on a device: the glass container
  composites it).
- **immersion** (owner's follow-up: "lets prioritize immersion"): the controls hide after **3 s**
  with no interaction, with a short fade (no movement, so Reduce Motion needs nothing else): in the
  square the language label and the expand button; full screen the language label, play/pause and
  collapse. They show when the square appears or full screen opens, then the 3 s run. A **tap
  anywhere** on the text brings them back and starts the 3 s again; while they show, every
  interaction starts it again (a tap, scrolling the lines, a control). **While hidden, the first tap
  only reveals**: a tap on a line doesn't seek then; once they show, it does. Hidden controls are
  **left out of the hierarchy** (`player.readAlong.language`, `.expand`, `.playPause`, `.collapse`
  don't exist), never faded: the glass container composites a glass control whatever its parent's
  opacity. **Never hidden** while VoiceOver runs, while the language menu is open, while the text
  isn't ready (*Preparing*, *Downloading*, *Not available*, *must be downloaded*, *Couldn't make*:
  the label may be needed) or while something covers them (the chapter panel; the full screen over
  the square, which comes back with a fresh 3 s on collapse). The model is
  `ReadAlongControlsVisibility`: one sleeping task per interaction, cancelled by the next, so only
  `ReadAlongContent` re-renders, and only when they flip. To know when the language menu is open, the
  label's menu is a clear UIKit button over the glass capsule (`ReadAlongLanguageMenuButton`, told
  `willDisplayMenuFor` / `willEndFor`): SwiftUI's `Menu` content fires `onAppear` once, the first
  time it opens, and `onDisappear` never (iOS 26.5). `-readAlongControlsHideAfter <seconds>`
  (Debug) changes the 3 s; the UI tests launch with 600, the immersion tests with 6 (the real 3 s
  ran out before XCUITest, at about a second a query, had checked the controls were there; the 3 s
  default is unit-tested).
- **tap a line:** seeks the loaded book to the line's start. On a book that isn't loaded it does
  nothing (it never loads or plays a book). While the controls are hidden it only brings them back.
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
  on this iPhone to show its text.* (an imported file that is not), *Couldn't
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
3. Tap **Cover** (the same pill) to go back.
4. With the text showing, tap the expand button in the square's bottom-right corner for full screen;
   the button in the same corner there collapses it.

## Driving it with abbay-ctl

```bash
$B launch -seedLibrary -seedPlayableBook -seedArtwork -resetSettings -seedReadAlong
$B tap library.toolbar.settings && $B wait settings.experimental.readAlong      # value "1" under -seedReadAlong; tap it to switch off (transcripts deleted)
$B tap library.row.<n>.title && $B wait player.close     # find "Seeded Playable Book" by title
$B tap player.text && $B wait player.readAlong.line.0    # the square replaces the cover
$B tap player.transport.play && $B snapshot              # the selected line moves on, a line every 4 s
$B tap player.readAlong.line.5                           # seeks to its start (loaded book)
$B tap player.readAlong.language                         # menu: English (checked), Portuguese
$B tap player.readAlong.expand && $B wait player.readAlong.fullScreen   # frame = the window's
$B tap player.readAlong.playPause                        # label Play <-> Pause, as the transport
$B tap player.readAlong.collapse                         # back to the square, its lines straight back
# wait 3 s without touching: player.readAlong.language and .expand are gone (full screen: .playPause,
# .collapse too); tap player.readAlong (or .fullScreen) to bring them back; a line tap then only reveals
$B launch ... -readAlongControlsHideAfter 600            # (Debug) keep the controls up while driving
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
- Full screen (`ReadAlongFullScreenUITests.swift`, part of `ReadAlongUITests`): the expand button
  sits bottom-right; `player.readAlong.fullScreen`'s frame equals the window's, its lines show
  without *Preparing text…*, the mini player and the player's close button aren't hittable under
  it; collapse brings the square back with its lines; its play/pause starts and stops playback; the
  expand button doesn't exist while the chapter panel is open and works once it closes.
- Immersion (`ReadAlongImmersionUITests.swift`, part of `ReadAlongUITests`, launched with a 6 s
  delay): the square's label and expand button stop existing after the delay, a tap on the square
  brings both back without moving the elapsed time, and they hide again; full screen, play/pause,
  collapse and the label hide and a tap on the text brings all three back (still *Play*); on the
  loaded, paused book a line tap while hidden only reveals (elapsed unchanged) and the next one
  seeks; with the language menu open past the delay the menu and the label stay, and once it closes
  the label hides. Unit: `ReadAlongControlsVisibilityTests` (the delay, reveal, restart, pinning,
  the never-hide conditions, the real clock, the launch argument). The cover and
  play/pause tests also pass on an iPad Air 13-inch (iOS 26.4) in its landscape split, where the full
  screen covers both panes. Unit: `ReadAlongFullScreenTests` (needs a presented player; ends on
  close, another book, a change of split, the owning screen's slot; stale once the screen follows
  another book), `ReadAlongViewTests` (the slot keeps the session shown while the square or the full
  screen shows it, the styles, the labels in en and pt-BR).
- Unit: highlight lookup, the store (keyed, deleted), the settings, language mapping and detection
  pick and region choice, the session (nothing runs while hidden, cancellation, saving, retarget,
  the ten-minute window, no run while scrubbing, a deleted book stays deleted), the store (saves
  queued, stamps), the detection sample's length and format, the line hint, the audio source
  (book time to files on the device), the transcriber's segmentation, `liveBookTime`, the menu's
  naming.

**Not driven by a UI test:** the status messages other than the stub's quick *Preparing text…*, the
scene-phase stop, a real LibriVox download finishing under the square, VoiceOver (including the
full screen's escape), the full screen ending on a fold or a book switch (unit-tested only), the
iPhone Duo (same root path as the iPad), the controls staying while VoiceOver runs or the text
isn't ready (unit-tested only: XCUITest can't run VoiceOver, and the stub is ready at once),
scrolling the lines as an interaction, and the **real engine**: its tests skip in the Simulator, so its proof is a
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
