# Siri — App Intents

The eight modern `AudioPlaybackIntent`s and the spoken phrases registered for them, plus, on iOS 27,
the App Intents audio domain. This is the half of Siri that Apple's `AppIntentsTesting` framework
can validate.

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
  `ChapterEntityQuery.entities(matching:)` resolves what was said through `matchChapters`
  (`Abbay/Intents/ChapterMatch.swift`, #206): a spoken position wins (digits: "4", "capítulo 3",
  "3rd"; or number words next to "chapter"/"capítulo", 1 to 99, cardinal or ordinal, en and pt-BR:
  "chapter three", "the third chapter", "capítulo vinte e um", "décimo primeiro capítulo"); then
  the chapter titles by the book-title rules (folding, stop words, word overlap; "chapter" /
  "capítulo" dropped at either end: "the prologue chapter", "o capítulo prólogo"), every tied
  chapter in book order; then number words alone ("three", when no title has them); then the one
  number in an otherwise unmatched request ("play chapter 4 please"). A number the book doesn't
  have falls through to the titles ("1984"). "chapter" or stop words alone match nothing.
  **What a number names is `ChapterNumbering`'s (#212):** the one chapter whose title carries it
  ("Chapter 1", "Capítulo Um", "Chapter IV", "Chapter 6: The Journey", a leading "1." / "1 -" /
  "1:"), so *Prologue, Chapter 1, …* plays *Chapter 1* for "chapter 1"; else the one-based position
  counted from the first chapter after the front matter (a leading run of titles whose first two
  content words include a `matterWords` entry: prologue/prólogo, introduction/introdução,
  preface/prefácio, foreword, apresentação, dedication, disclaimer, …; a leading "00 -" track
  number doesn't count). A trailing run of the same words (epilogue/epílogo, afterword/posfácio,
  appendix) is back matter. Front and back matter have no number and are asked for by title. A
  position whose title carries another number names nothing; two titles with the same number
  ("Chapter 1" in two parts) leave it to the position. A book with neither numbered titles nor
  front matter, or one that is all front matter, is numbered by position as in #206.
  `ChapterEntity` carries that `number` (nil for front/back matter) and its `title`: it shows
  *"Chapter N"* / *"Capítulo N"*, or the title when it has no number, so the expanded
  *"Play \<chapter> in Abbay"* phrases match the numbering. The dialog says *"Playing chapter N."*,
  or *"Playing \<title>."* for an unnumbered chapter. Cases: `SpokenChapterMatchingTests`,
  `SiriEntityTests`, and `AudioDomainUITests.test_chapterShortcut_jumpsToTheChapterNamedByItsTitle`
  (no seed has front matter, so the offset is unit-tested only; spoken check #220).
- **PlayAuthorIntent (#213)** — takes an `AuthorEntity` (`Abbay/Intents/AuthorEntity.swift`):
  *"Play \<author> in/on Abbay"*, pt-BR *"Tocar \<author> no Abbay"*. The authors are the library's
  distinct artists (`LibraryAuthors.all`: library order, the last-played book's author first, empty
  artists dropped, spellings that fold alike are one author under the first spelling).
  `AuthorEntityQuery` suggests 15 (phrase budget), resolves ids against the current library, and
  `entities(matching:)` reads what was said as an author by #207's rules ("jane austen", "something
  by jane austen", "um livro do machado"). It plays `LibraryAuthors.book`: the author's last-played
  book, else their first in library order (artist folded equal to the name; `matchAuthor` if none
  is). No book: *"No audiobook by \<author> in Abbay."* / *"Nenhum audiolivro de \<author> no
  Abbay."* The suggestions refresh with the library through `SiriLibraryPublisher`'s
  `updateAppShortcutParameters()` (see [siri-library-publish](siri-library-publish.md)). Cases:
  `AuthorEntityTests`, `AppShortcutPhraseTests`, and through `AppIntentsTesting` on iOS 27
  (`AudioDomainUITests.test_authorShortcut_playsTheAuthorsLastPlayedBook`). Spoken, on a device:
  unchecked (#220).
- **moved books (#186):** every intent finds a book by its identity, the URL its row was saved
  under (last played, entity ids, the library's `url`), so a book whose file moved is resumed,
  played by name or entity and has its chapters found. `MovedBookIdentityTests` drives
  `ResumeAbbayIntent`, `AudiobookEntityQuery` → `PlayAudiobookIntent` and `PlayBookByNameIntent`
  over real Core Data with a stubbed bookmark resolver.
- **phrase-registration:** `AbbayAppShortcuts` registers all eight. Entity phrases lead with the app
  name on purpose — Siri completes a known media title from registered vocabulary and then ends the
  utterance, so establishing the app first means a truncated tail costs nothing. Every "in Abbay"
  phrase also has an "on Abbay" twin (plus *"Play Abbay"* and *"Play \<title> using Abbay"*):
  without them, *"Play \<title> on Abbay"* matched no Abbay phrase and Siri sent it to the default
  music app. `AppShortcutPhraseTests` reads the shipped `Metadata.appintents` to pin the variants and
  keeps the total under Apple's 1,000-phrase cap, counting pt-BR on top of English (entity phrases
  × 40 books / 50 chapters / 15 authors). **The total is exactly 1,000 since #213** (955 before it,
  plus 3 author phrases × 15): a new entity phrase needs a smaller limit somewhere (#219).
  *"Play something by \<author> in Abbay"* is not registered for that reason; Siri hands it to
  SiriKit's media routing (#207).
- **audio-session guard:** every intent begins with `AudioSessionActivator.attemptActivation()`
  (the container's `audioSessionActivator`, #153) and returns *"Audio temporarily unavailable. Try
  again in a moment."* on failure.
- **audio-domain (iOS 27+, #129):** `Abbay/Intents/AudioDomainIntents.swift`, all
  `@available(iOS 27, *)` (the deployment target stays iOS 17; on 17–26 nothing here exists and
  SiriKit's `INPlayMediaIntent` plus the App Shortcuts above do the work).
  - `AudioDomainBookEntity` is `@AppEntity(schema: .audio.audiobook)` (schema `MediaBookEntity`):
    id = the book's URL string, `title`, `author` (the model's artist); the schema's other
    properties (`genre`, `narrator`, `publisher`, `seriesTitle`, `releaseDate`, `purchaseDate`) are
    required by the metadata processor and always nil.
  - `AudioDomainBookQuery` is an `EntityQuery` plus `IntentValueQuery` over
    `MediaIntents.AudioSearch`. Siri hands it the request's `criteria`: `.searchQuery(text)` →
    the same fuzzy title rules as the other paths (`matchAll`, which tolerates extra words, an
    author and pt-BR articles since #201, and author-only requests since #207; see
    [siri-playmedia](siri-playmedia.md) *matching*); `.unspecified` ("play an
    audiobook") → the library, last-played first, capped at 40; `.url([URL])` → books whose URL
    or saved row URL matches. The mapping is the pure `AudioDomainMatcher`, unit-tested on every
    runtime.
  - `PlayAudioDomainIntent` is `@AppIntent(schema: .audio.playAudio)`. Its `audioEntity` is the
    `@UnionValue` `AudioDomainItem`, which keeps only the `audiobook` case. `playbackAttributes`
    (default empty) and `queueLocation` are accepted and ignored (an audiobook plays in order, and
    Abbay has no queue); `warmupAudioQueueResult` is a transient entity that Abbay never produces.
    It plays through the same `abbayPlayBook(at:)` as `PlayAudiobookIntent`: *"Playing \<title>."*
    or the cannot-find dialog (clearing a dead last-played pointer).
  - Diagnostics: `appintent PlayAudioDomainIntent fired`, `query audio search <kind> found=N`
    (the kind, never what was said) and `query audio book byId asked=N found=N`.
  - The case labels the schema enums show in Shortcuts (*Shuffle*, *Repeat*, *Play next*,
    *Play last*) are in `Localizable.xcstrings` in `en` and `pt-BR`.
- **diagnostics:** every intent calls `DependencyContainer.diagnostics.record("appintent <Name> fired")`
  first: the App Group trail in the app, an in-memory one under `MockDependencyContainer` (#153).

## How to get to it (user POV)

Speak a phrase, or run the shortcut from the Shortcuts app / Spotlight. Phrases include *"Play in
Abbay"* / *"Play on Abbay"*, *"Pause Abbay"*, *"Next chapter in/on Abbay"*, *"Abbay play \<title>"*,
*"Play \<title> on Abbay"*, *"Play \<chapter> in/on Abbay"*, *"Play \<author> in/on Abbay"*.
Speaking phrases needs a real device;
the simulator can only run the shortcuts.

## Driving it with abbay-ctl

The *voice* path is `verified-unreachable` — Siri cannot be invoked in the simulator. The *intent*
path is reachable two ways:

```bash
$B diagnostics --clear
# ... trigger however possible ...
$B diagnostics                                # assert "appintent <Name> fired"
$B appgroup get abbay.lastPlayedAudioURL
$B wait miniPlayer.bar                         # in-app proof that a book was loaded (see mini-player.md)
```

The durable answer is **`AppIntentsTesting`** (Xcode 27 / iOS 27 SDK): it executes intents through
the real App Intents stack with no UI automation and no mocks, building `IntentDefinitions` from the
bundle identifier so the test never imports the app target. It runs in the UI-test bundle on an
iOS 27 simulator, while the app itself stays on iOS 17. **Verified** for the audio domain by
`AudioDomainUITests` (skipped below iOS 27):

- `test_audioSearch_findsASeededBook_andPlayAudioPlaysIt`: launch `-seedLibrary`,
  `valueQueries["AudioDomainBookQuery"].values(for: AudioSearch(criteria: .searchQuery("Seeded
  Chaptered")))` returns one `AudioDomainBookEntity` titled *Seeded Chaptered Book*, then
  `intents["PlayAudioDomainIntent"].makeIntent(audioEntity:).run()` loads it: `miniPlayer.bar`
  appears with that title.
- `test_audioSearch_withExtraWords_findsOnlyThatBook`: `.searchQuery("the seeded chaptered book
  by Seed Author")` returns exactly *Seeded Chaptered Book*, not the other *Seeded … Book*s by the
  same author (#201).
- `test_audioSearch_authorOnly_carriesOnWithThatAuthorsLastPlayedBook` (#207): plays *Seeded
  Plain Book* through `PlayAudioDomainIntent`, then `.searchQuery("something by Seed Author")`,
  `"um livro do Seed Author"` and `"seed author"` each return exactly that book (author *Seed
  Author*), and `"something by Nobody Else"` returns nothing. The last-played pointer survives a
  launch, so the all-of-their-books case (none of theirs played last) is unit-tested only.
- `test_audioSearch_withNoTitle_offersTheLibrary`: `.unspecified` returns the seeded books.

What it can't cover: Siri's speech recognition and its choice of Abbay over other audio apps. That
needs an iOS 27 device: #201.

## Gotchas

- **Dialog strings are spec-locked and unit-tested.** They are lifted into `static let`s precisely
  so a reworded response fails a test. Fix state, not wording.
- The dialogs are `LocalizedStringResource`s with `en` and `pt-BR` in `Localizable.xcstrings`
  (`siri…` keys), resolved in the Siri language; the pt-BR phrases are in `AppShortcuts.xcstrings`.
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
