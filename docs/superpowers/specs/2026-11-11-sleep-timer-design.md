# Sleep timer, and back to where you fell asleep (#332)

## Why

Bedtime listening is a core audiobook use. Nicolas asked (2026-11-09) for a sleep mode like Apple
Books': set it, and after a while the book pauses. Apple Books stops there; Abbay adds a way back to
where you dozed off, because losing your place after falling asleep is the main frustration.
The store listing currently says there is no sleep timer (`StoreConfig/README.md`), so this also
becomes a listing feature.

## Scope and order

Two PRs into `develop`, back to back (owner, 2026-11-11):

1. **Sleep timer** — the timer, the moon pill, the fade, the pause.
2. **Back to where you fell asleep** — the prompt after a timer pause, saved per book.

Part 2 builds on part 1's "the timer paused the book" event. Each PR follows `CLAUDE.md` (feature
map, live check, issues for gaps, before/after screenshots in en and pt-BR, local gate).

**Non-goals (both parts):** CarPlay controls, Siri ("set a sleep timer"), a moon on the mini player,
anything on the lock screen or Now Playing beyond the usual paused state, shake-to-extend. File
issues for any that seem worth having.

**Anti-goals:** touching the system volume; the timer silently dying when the player screen closes
or the app goes to the background; Abbay's saved volume level changing because of the fade.

## Part 1: the sleep timer

### Choices
Off, *When current chapter ends*, 5, 10, 15, 30, 45 minutes, 1 hour (Apple Books' set).
*When current chapter ends* is offered only when the loaded book has chapters (found ones, #321,
included). Durations are wall-clock listening time, not book time: at 2× speed, 15 minutes is still
15 minutes.

### On the player
- **A fourth left-hand pill:** speed · volume · 🌙, then Text and Chapters on the right (Apple Books
  puts its moon beside the speed). Idle, it is icon-only (`moon`), the volume pill's size. Running
  a duration, it shows the time left, `🌙 12:34` (monospaced digits, minutes:seconds; `1:00:00`
  for the hour). Running *end of chapter*, a filled moon (`moon.fill`) with no time. *(builder's
  call: idle tint white, running tint malachite, like a non-1× speed.)*
- **A tap opens a menu** (SwiftUI `Menu`) listing the choices, with the running one checked. While a
  timer runs, *Off* cancels it and any other choice replaces it.
- **Room:** with Read-along on, four pills already share a 393 pt iPhone row (#313). The speed must
  never shrink; Text and then Chapters drop to their icons first (existing `collapsesToIcon`). The
  running moon's `12:34` must not truncate either. When the row still runs short (iPhone SE with
  Read-along on, large Dynamic Type, landscape beside the cover), things give way in this order:
  Text drops its word, then Chapters, then the running moon drops its time and shows only
  `moon.fill` (VoiceOver still reads the time left). The speed never shrinks. *(my call)* Check on
  the narrowest supported iPhone (SE) and in landscape, at default and large Dynamic Type,
  Read-along on and off.
- **VoiceOver:** label *Sleep timer*; value *Off*, *12 minutes left* (whole minutes, rounding up;
  *less than a minute left* under 60 s), or *When current chapter ends*.
- **Ids:** `player.sleepTimer` on the pill; menu items addressable by their titles in UI tests
  (or ids if a `Menu` keeps them; builder decides and documents in `AccessibilityID.swift`).
- **Which book:** the timer belongs to playback, not to a book. Switching books keeps it running.
  *(my call)*

### Counting
- The countdown runs only while playing. **A pause (manual, an interruption such as a call, or
  anything else) holds the countdown; play resumes it.** Only *Off* cancels it.
  *(my call, overriding the issue's "pausing cancels it": a 2 a.m. pause or a phone call would
  otherwise leave the book playing all night once resumed. Owner may overturn.)*
- It lives app-wide, beside `PlaybackCenter` (built once in `DependencyContainer`), never in a
  view, so it keeps counting with the player closed, in the background and on the lock screen (the
  audio background mode keeps the process alive while playing). It must not rely on a view's
  `.task` or a `Timer` on a run loop that stops in the background; base it on elapsed playing time
  (e.g. the playing-state publisher plus a monotonic clock), not on counting ticks.
- Unloading the book (it was deleted) cancels the timer.
- Not persisted across app termination: a killed app isn't playing anyway. *(my call)*

### The end
- **Duration:** when the time left reaches the fade length (about 5 s), Abbay's own volume ramps
  down to silence, then the player pauses, then the volume is restored to the listener's level.
  The ramp is applied to the queue player's gain/boost directly, **not** through `setVolume`
  (which saves the level). A user volume change during the ramp ends the ramp and keeps their new
  level; the pause still happens.
- **End of chapter:** the same fade, timed to finish at the end of the chapter that is current
  (in book time, scaled by the speed). The book must pause at the boundary: no more than about
  half a second of the next chapter may be heard. This includes LibriVox books, where a chapter
  is a file and the queue moves to the next file on its own (`MultiFileQueue`). A manual jump to
  another chapter while it is armed re-targets the end of the chapter now playing. *(my call)*
  If the book has no next chapter, the book's end already pauses it; the timer just clears.
  If the playing book has no chapters (the timer followed a switch to such a book, or its found
  chapters were removed), *end of chapter* means the end of the book. If the chapter list is
  replaced while armed (a chapter search, #323), it re-targets the chapter now current.
  *(my calls)*
- **The book ends while any timer is set** (timed or end of chapter): the timer clears, and this
  counts as the timer stopping the book (part 2 saves a spot): the listener likely slept through
  it. *(my call)*
- **After it fires:** the timer is Off, the pill is idle again, and the event "the timer stopped
  book X at book time T; last awake at book time S" is published for part 2 (see *The spot*).
- Lock screen / Now Playing show the book paused, as for any pause.

### Testing hooks
- A launch argument, e.g. `-sleepTimerSeconds <n>`, adds an extra short choice (or makes every
  duration that many seconds) so UI tests can see the countdown, fade and pause in a few seconds.
  Debug only, like the others in `DebugSupport`. Documented in `LaunchArgument.swift`.
- Unit tests: counting only while playing; pause holds, play resumes; Off cancels; replacing a
  choice; end of chapter (single-file chaptered book and multi-file book); re-target on a chapter
  jump; volume restored and not saved after the fade; user volume change mid-fade; unload cancels.
- UI tests: set a short timer, see the countdown, see the book pause and the pill go idle;
  *When current chapter ends* absent for a book with no chapters.

### Strings (en + pt-BR, `Localizable.xcstrings`)
*Sleep timer* / *Timer de sono*; *Off* / *Desligado*; *When current chapter ends* / *Ao fim do
capítulo atual*; *5 minutes* … *1 hour* (pt-BR *5 minutos* … *1 hora*); the VoiceOver values.
pt-BR wording is the builder's call within the app's existing tone.

### Docs
`player.md` gains a *sleep-timer* sub-feature (and a new page if it grows); `StoreConfig/README.md`
drops "There's no sleep timer, so it isn't claimed."

## Part 2: back to where you fell asleep

### The spot
When the timer stops a book (part 1's event), Abbay saves, **for that book**, `S`: the book time
of the listener's **last deliberate action** while the timer ran, because they were certainly
awake then. Part 1 tracks it: setting or changing the choice, pressing Play, a seek, a skip or a
chapter tap (from the app, the lock screen or CarPlay) each move `S` to where playback stands
after the action. A book switch under the timer sets `S` to where the new book starts. Automatic
moves (a chapter ending into the next) don't. *(my call; the issue's "where the timer started" is
the case with no action after arming.)*
Saved per book, keyed like the per-book speeds (`AppSettings`), so it survives relaunch.

### The prompt
- On that book's player, a visible glass capsule over the bottom of the cover, modelled on the
  *Resumed at 3:20 · Start over* prompt (#299, `ResumePromptView`), with the moon:
  *🌙 Back to where you fell asleep · 1:02:13* (the target as book time, `PlayerProgressView.clockText`)
  and a small ✕. It never sits under the open chapter panel, and it doesn't time out.
- A tap seeks the book to `S`, clears the spot and the prompt, and does not start playback.
  ✕ clears them without seeking.
- It also clears when: a new sleep timer is set on that book; playback of that book **starts** more
  than 5 minutes (book time) from where the timer stopped it (`T`), e.g. a chapter tap or a long
  scrub, while small skips and scrubs near `T` keep it; or 30 minutes of further listening have
  passed since the stop. Moves while paused don't clear it by themselves. *(my call: pressing Play
  at or near the stop keeps it, because a half-asleep listener may press Play or back-15 on the
  lock screen before seeing the prompt.)*
- VoiceOver announces it when it appears, like the resume prompt. Ids
  `player.sleepReturn` (message) and `player.sleepReturn.go` / `.dismiss`.
- Not on the lock screen, CarPlay or the mini player.

### Testing
Unit: spot saved on a timer pause only (not a manual pause), saved value survives a new
`AppSettings`, each clearing rule, the book-switch case. UI: short timer pauses, prompt appears,
tap returns to `S`; relaunch keeps the prompt.

### Docs
`player.md` *sleep-timer* gains the prompt; `StoreConfig/README.md` may mention it.

## Constraints
iOS 17.0 floor (gate newer APIs with `@available`); strings in en and pt-BR; no change to the
LibriVox download layer's closures; SwiftLint strict; one simulator per run with
`-parallel-testing-enabled NO`.

## Left to the builder
Type names and file layout; the exact fade curve and length (4–6 s); how the end-of-chapter pause
is made exact (boundary time observer, item-end notification, or tick math); menu-item ids;
pt-BR phrasing.
