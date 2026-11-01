# Find chapters (experimental)

An imported book with no chapter markers (a plain MP3, the common case) gets its chapters from
**its own audio**: read-along's on-device speech engine (`SpeechTranscriber`, iOS 26 and later)
transcribes the whole file, and a chapter starts wherever the narrator reads out a heading
("Chapter Three", "Part II", "Capítulo 4", "Prologue"). Opt-in: its own switch in
[Settings](settings.md) › Experimental, off by default, **independent of Read-along** (owner: "this
should be an experimental feature too"). Nothing is sent anywhere and nothing is downloaded but
iOS's speech model for the book's language, the first time it is needed.

The pieces: `AppSettings.findChaptersEnabled` (the switch); `ChapterFinder` (offered or not, the
search, its progress, saving, removing; owned by `ReadAlongCenter.chapters`, so it shares the
engine); `ReadAlongLanguageResolver` (the book's language, the same way the read-along text picks
it); `ChapterHeadingDetector` (pure: transcript → chapters); `SaveChaptersUseCase` (replaces a
saved book's chapters); `PlayerView`'s `FindChaptersPill`; the chapter list's footer.

## Sub-features

- **switch** (`settings.experimental.findChapters`, *Find chapters* / *Buscar capítulos*): its own
  section under Read-along's, iOS 26+ and only where the engine runs (`ReadAlongCenter.isAvailable`;
  `-stubReadAlongEngine` in the Simulator). Off by default. The footer says it listens to the whole
  book on the device for headings such as "Chapter One", can miss or misplace some, found chapters
  can be removed from the chapter list, nothing is sent. **Shown while VoiceOver runs** (unlike
  Read-along's switch: found chapters help a listener who can't see the screen): with VoiceOver on
  this section carries the *Experimental* header itself. Rule: `SettingsView.showsFindChapters`.
  Switching it off stops a search; chapters already found stay, and so does their *Remove* button.
- **pill** (`player.findChapters`): in the [player](player.md)'s pill row, in the Chapters pill's
  place, for an **imported** book (not LibriVox) with **no chapters**, while the switch is on.
  *Find chapters* / *Buscar capítulos* with `text.magnifyingglass`; VoiceOver hint *Listens to the
  book on this device for chapter headings.* A tap starts the search. Like Chapters, it keeps its
  word longer than Text and drops to its icon when the row runs short.
- **searching:** the pill reads *Finding 34%* / *Buscando 34%* with `xmark` (VoiceOver *Finding
  chapters, 34%*, hint *Stops finding chapters.*); a tap stops the search and saves nothing. The
  search belongs to the app (`ChapterFinder`), not the screen: closing the player or opening
  another book doesn't stop it, and the pill shows its progress when the book is opened again. One
  search per book. The language is the book's read-along language, else detected (a 20 s sample
  scored with each installed model, from 10% into the book, at most 5 min, past an opening of music),
  and saved for the book, so the read-along text then uses it too. A model iOS offers is
  downloaded first (the pill stays at 0%). Speed: the engine runs about 70× real time on an iPhone
  15, so a 10-hour book takes roughly 9 minutes.
- **headings** (`ChapterHeadingDetector`): a keyword **after at least 1 s of silence** (or as the
  first word): *chapter, part, book, section, volume* / *capítulo, parte, livro, seção* / *capítulo,
  parte, libro, sección, tomo* followed by a number (digits, a Roman numeral up to LXXXIX, number
  words with *and/e/y* between them), or on their own *prologue, epilogue, introduction, preface,
  foreword, afterword, prelude* and their Portuguese and Spanish words. "as we saw in chapter two"
  is not one (no pause before it). The number ends at the narrator's next pause and nothing follows
  digits ("Chapter 2. … One time, when I…" is *Chapter 2*). A heading within 30 s of the one before
  is a repeat when it is the same kind (LibriVox reads "Chapter 1 of Emma… Chapter 1.") and joins
  it when it isn't ("Part one. The Tribute. Chapter one." is *Part One · Chapter One*). Titles are
  as said, capitalised: *Chapter Twenty-One*, *Part II*, *Capítulo Vinte e Dois*. Audio before the first heading is an
  **Opening** / **Abertura** chapter when longer than 30 s; a shorter lead-in joins the first
  chapter. **Fewer than two headings is no chapters.**
- **shown as they are found** (owner: "start navigating instead of waiting"): from the second
  heading on, the chapters so far are saved and shown while the search goes on, and again at each
  new heading; the latest one runs to the end of the book until the next is heard. The Chapters
  pill then reads *Chapters 34%* / *Capítulos 34%* (VoiceOver value *Finding more, 34%*), and the
  chapter list ends with *Finding more chapters… 34%* and **Stop finding** / *Parar a busca*
  (`player.chapters.stopFinding`). A chapter that starts where it did keeps its resume offset
  across updates (`SaveChaptersUseCase` merges by start, within 0.5 s), so listening while the
  list grows loses nothing. The detector reruns only after text holding a heading keyword
  (`ChapterHeadingDetector.mayStartHeading`), and the chunk after it.
- **found:** saved to the book's Core Data row like a file's own chapters (the Siri/CarPlay
  snapshot is rewritten), and the book is marked (`AppSettings.foundChapterBooks`). At once: the
  Chapters pill replaces *Find chapters*; the library row reads *Ch N/M*; the loaded book's player
  (Next/Previous chapter, chapter taps, the lock screen, Siri's *Play chapter*) and CarPlay's Now
  Playing chapter list use them (`PlaybackCenter.replaceChapters`, `.bookChaptersDidChange`). Chapter
  resume (#299) works on them as on any chapters.
- **none found:** banner *No chapter headings were heard in this book.* / *Nenhum título de
  capítulo foi ouvido neste livro.*; the book is unchanged and the pill comes back.
- **file missing:** the moved-file banner (*fileMissing*), as for Play.
- **failed** (no speech model for the language, the engine failed, the app was suspended mid-run):
  banner *Couldn't search this book for chapters. Try again in a moment.* Chapters already shown
  stay, as they do after **Stop finding**, the switch going off, or the app being killed.
- **continue** (#316, `player.chapters.continueFinding`): how far the transcription got is saved
  with the book (`AppSettings.chapterSearchCoverage`, seconds; at each new chapter, at least every
  120 s of audio, and when the search ends). While that is short of the book's end (owner: "just
  look if the transcription analyzed the whole audio"), the chapter list ends with *Stopped at 45%
  of the book.* / *Parou em 45% do livro.* and two buttons: **Continue finding** / *Continuar a
  busca* and *Remove found chapters*. Continue starts from the **start of the last chapter found**
  (it ran to the end of the book because its successor hadn't been heard, and a heading cut off at
  the stop is heard whole); the chapters before stay, its own heading isn't added twice
  (`ChapterHeadingDetector.extending`), and the ones after are added as found. A search that
  reaches the end saves the book's whole length: no Continue. Chapters found before #316 have no
  coverage and count as complete. Removing the chapters forgets the coverage. Continue needs the
  switch on; the *Stopped at* line shows either way.
- **remove** (`player.chapters.removeFound`): at the end of the chapter panel (and the chapters
  pane), only for found chapters and once the search has ended (beside Continue when it stopped
  short): *Found by listening to the
  audio.* and a button *Remove found chapters* / *Remover capítulos encontrados* (trash). A tap removes them (row, mark, player), the
  panel closes and *Find chapters* comes back. A file's own chapters never show it. The panel grows to
  fit the footer (it is sized from its measured content, see [player](player.md) *chapter-panel*).
- **not kept:** the transcript the search makes is not saved (the player's read-along session may
  be writing the same book's text); deleting the book drops its mark.

## How to get to it (user POV)

Settings › Experimental › *Find chapters* on. Import an MP3 without chapters, open it, tap *Find
chapters* in the bottom right of the player.

## Driving it with abbay-ctl

```
$B launch --seed-library --reset-settings -stubChapterHeadings   # switch on, stub engine with headings
$B tap library.row.<plain>.title          # Seeded Plain Book: no chapters
$B wait player.findChapters
$B tap player.findChapters                # label "Finding chapters, N%" for about 4 s
$B wait player.chapters                   # Chapter One, Chapter Two while it goes on (value "Finding more, N%")
$B tap player.chapters                    # player.chapters.stopFinding at the list's end
$B wait player.chapters.removeFound       # done: Chapter One 0:00, Chapter Two 1:10, Chapter Three 2:10
# or: $B tap player.chapters.stopFinding → player.chapters.continueFinding appears ("Stopped at N% of the book.")
#     $B tap player.chapters.continueFinding → transcribes from Chapter Two's start, adds Chapter Three
$B tap player.chapters
$B tap player.chapters.removeFound        # panel closes, player.findChapters is back
```

`-stubChapterHeadings` (implies `-stubReadAlongEngine`; with `-resetSettings` the switch is on in
the in-memory settings) makes the stub read out "Chapter One." at 10 s, "Chapter Two." at 70 s and
"Chapter Three." at 130 s, each after a 2 s pause, in 10 s steps 500 ms apart (about 10 s). Without it
(`-stubReadAlongEngine` and the switch on by hand) the canned text has no headings: *No chapter
headings were heard*.

**Evidence:** `AbbayUITests/FindChaptersUITests` (switch off → no pill; progress, the first
chapters with Stop while it goes on, three chapters, remove; stop before any heading; Stop from the
list keeps them and Continue finds the rest; the Settings switch and footer in en and pt-BR). Unit: `ChapterHeadingDetectorTests`,
`ChapterFinderTests`, `FoundChaptersTests`, `SettingsViewExperimentalTests`.

## Gotchas

- The Simulator has no real engine: only the stub is driven. The real engine runs on a Mac (macOS
  26+): a 10.6 h single-file MP3 of a commercial audiobook (27 chapters in three parts, joined from
  its per-chapter files, so the true boundaries were known) transcribed in 10 min on this Mac and
  gave all 27 chapters within 2 s of the true starts, with no false ones, plus a 52 s *Opening*
  (credits). Its trailing credits and interview stay in the last chapter (no heading). An iPhone
  run is still a device check.
- A search runs while the app runs: a suspended app can end it with *Couldn't search*. Playing
  audio keeps the app running.
- `PlaybackState.setLoadedBook` ignores a book with the same URL, so chapter changes to the loaded
  book go through `setLoadedBookChapters`; a book opened without playing gets them through
  `PlayerViewModel.presentedChaptersChanged` (its one observable property).
