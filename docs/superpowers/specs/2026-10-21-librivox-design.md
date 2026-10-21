# LibriVox Integration: Design

**Date:** 2026-10-21
**Status:** Draft, open questions answered; pending Edson's approval
**Mockups:** `.superpowers/brainstorm/18651-1792598022/content/` (`entry-point-v3.html`, `details-download.html`)

## Why

Today you can only add a book by importing a file through the document picker. That's a poor first
experience for App Store reviewers, who have to find and load their own audio file to try the
app. It's also awkward for real users, who have to download a book somewhere else and then move it
into Abbay. [LibriVox](https://librivox.org/) is a catalog of free, public-domain audiobooks with
a public JSON API and no key. Building it in lets a user search, download and play a book without
leaving the app. File import stays exactly as it is.

## Goals

1. Users can search LibriVox from the Library screen, open a book's details page and download it.
2. **Playback starts before the download finishes.** Chapters download in order. You can play
   right away, and jumping to a chapter that isn't downloaded yet streams it.
3. **A book can span several audio files.** A LibriVox book is one library item made of its
   section MP3s, and each section is a chapter. Player, chapter list, chapter counter, lock screen,
   CarPlay, Siri and Spotlight all treat it as one book and move between files seamlessly.
4. **NetworkProvider gains a download feature** for large files: it writes straight to disk with
   progress, pause/resume and cancellation, and keeps going in the background. It's written
   generically so Edson can bring it back to the iOSProjectSetup template.
5. Imported single-file books with embedded chapters keep working with no change in behavior.

## Non-goals

- A settings screen. The ⚙️ toolbar button stays as it is (it does nothing today).
- Catalogs other than LibriVox.
- Accounts, sign-in, favorites, ratings or recommendations beyond what the LibriVox API returns.
- Rebuilding the iOSProjectSetup Tuist setup inside Abbay (see Constraints).

## Anti-goals (failure even if it "works")

- **Breaking imported books.** Existing libraries, saved positions, bookmarks, CarPlay and Siri
  for single-file books must behave exactly as they do today.
- **Sending listening data anywhere.** Abbay's pitch is no tracking and no data collection. The
  only network traffic is search, metadata and audio from librivox.org and archive.org, with no
  analytics or identifiers.
- **Pulling in third-party dependencies.** Everything stays native Swift/SwiftUI. NetworkProvider
  is Edson's own code.
- **Spending a user's cellular data on a large book without asking** (see the cellular warning
  under Downloading).

## Constraints

- iOS 17.0 deployment target, iPhone only, Xcode 26, Swift 5 mode, XcodeGen (`project.yml`),
  SwiftLint post-build script.
- **NetworkProvider source:** `ProjectContent/Modules/NetworkProvider` on the
  `tuist+modules+agentic` branch of https://github.com/EdYuTo/iOSProjectSetup (the branch
  matters). **Copy the source in and ignore the Tuist build setup**: no `Project.swift`, no Tuist.
  The builder decides where the code lives and how it compiles, with the least ceremony that works
  under XcodeGen and SwiftLint. Its tests come along and must pass.
- NetworkProvider today has one `URLSession.data(for:)` call behind the internal
  `URLSessionDataLoading` seam. It loads the whole response into memory, which is fine for search
  JSON but not for audio. The new download feature should follow the same conventions:
  protocol-first public API, an internal test seam, `NetworkError` mapping, cooperative
  cancellation, and no Abbay-specific types.
- **Book identity is `AudioModel.url` everywhere today:** `Player.url`, `isPlaying(_:)`,
  `LastPlayedStore`, the CarPlay progress row (#108 tracks it by playing URL), the Siri library
  snapshot, Spotlight, the `ForEach` identity in `MediaListView`, and `LoadAudioRepository`
  lookups. A multi-file book still needs **one stable identity URL**, and each chapter needs its
  own file URL.
- **The position is a single number.** `AudioModel.currentTime` and `ChapterModel.startTime`
  measure time from the start of the book. For multi-file books, keep that meaning: chapters'
  `startTime` are cumulative across files, and the saved position is a time within the whole
  book. The player maps it to (file, offset) internally. This keeps `currentChapter(for:)`, the
  progress bar, Now Playing and the intents working without changes at each call site.
- Core Data model `AudioDataModel` / `ChapterDataModel` has no version history yet. Adding fields
  needs a lightweight migration that existing installs survive.
- Background audio (`UIBackgroundModes: audio`) is already enabled. Background downloads need
  `URLSession` background configuration plus the app-delegate wake-up handler.
- Privacy manifests were just added (#110). Check whether network access to librivox.org and
  archive.org changes anything in them or in the App Store privacy answers (it shouldn't, since
  no data is collected), and update the README's privacy section to mention the network use.

## The experience

### Library screen (mockup `entry-point-v3.html`)

One Library screen with no tab bar.

- **Toolbar:** ＋ and ⚙️ at the top right. The old 🔍 and 📁 buttons are replaced by ＋.
- **＋ menu:** offers **Browse LibriVox** and **Import file**. Import file is today's document
  picker, unchanged.
- **Empty library:** big **Browse free audiobooks** (primary, malachite green `#0BDA51` with dark
  text) and **Import a file** (secondary, onyx `#353539`) buttons. No search bar while the
  library is empty.
- **Library with books:** a search bar under the title. **One search covers both sources**,
  showing an **In your library** section (local matches, with a "Downloaded" tag where relevant)
  and an **On LibriVox** section (remote results, each with a ↓ affordance).
- **Browse LibriVox** (from ＋ or the empty state) opens the same search with an empty query and
  shows popular or recent LibriVox books before you type anything.
- Colors come from `ColorConstants`. Accents are malachite green, matching play/pause, the
  progress bar and the playing title. **Don't use `maximumRed`**: it's in the palette but no view
  uses it, and Edson rejected it in the mockups.

### Book details page (mockup `details-download.html` ①)

Opened from a LibriVox search result. It shows:

- cover, title, author, total length, chapter count, language, and **download size** (whole
  book), with the description truncated behind "More"
- a primary **↓ Download** button
- the chapter list with durations
- a footer credit: "Public domain recording by LibriVox volunteers"

### Downloading and playing (mockup `details-download.html` B, chosen)

- The LibriVox details page is **only for books not yet in the Library**. A search result for a
  book you already have appears only under "In your library" (*my call*) and behaves like a
  Library row.
- Tapping Download adds the book to the Library **right away** and starts downloading chapters in
  order. The details page then shows **▶ Play**, an overall progress bar, and each chapter's
  state: ✓ downloaded, a percentage while downloading, or "waiting".
- **After that, the book's existing detail page is the home for its download state.** Tapping a
  Library row opens the existing `PlayerView` sheet, as it does today. For LibriVox books, its
  chapter list also shows the per-chapter state (✓ / % / "waiting"), with a thin green overall
  progress bar under the Chapters header. Imported books look exactly as they do now. The row's
  ▶ button keeps playing in place, as today.
- Play works right away. If the chapter you need isn't on disk yet, it **streams** from
  archive.org. Jumping to a chapter moves it to the front of the download queue.
- The Library row also shows a progress ring while downloading. The book stays fully visible (not
  dimmed) because it's already playable. Tapping the ring pauses the download, and tapping again
  resumes it.
- Downloads keep going when the app is in the background or the phone is locked, and resume
  after the app is closed.
- Deleting the book (the same swipe-to-delete as today) cancels any download in progress and
  removes its files.
- **Cellular warning:** if the device is on cellular and the whole book is **larger than 99 MB**
  (the sum of all chapters), show an alert along the lines of *"You're trying to download a large
  file. Are you sure you want to proceed?"* with **Continue** and **Wait for Wi-Fi**. "Wait for
  Wi-Fi" queues the download until Wi-Fi is available. *My call:* the warning only appears on
  cellular, since on Wi-Fi there's nothing to choose.
- **Switching networks mid-download (Edson's decision):** if the phone moves from Wi-Fi to
  cellular, the download **pauses** until Wi-Fi returns, *unless* the user chose **Continue** for
  that book. That choice is saved per book and survives a relaunch (*my call*). Books under 99 MB
  never trigger the alert, and are treated as if Continue had been chosen.
- **Streaming is always allowed (Edson's decision):** pressing Play on a chapter that isn't
  downloaded streams it, even on cellular and even if the book is waiting for Wi-Fi. That's a
  choice the user made themselves. Streaming doesn't count toward the 99 MB limit.
- **Offline:** search shows an offline message, and downloaded chapters still play.
- Once a book is in the Library, CarPlay, Now Playing, Siri and Spotlight treat it like any other
  book.

## LibriVox data notes

- Search: `GET https://librivox.org/api/feed/audiobooks/?format=json&extended=1&title=^<query>`
  (also supports `author=`, `limit`, `offset`). It returns `id`, `title`, `description` (HTML),
  `authors[]`, `language`, `totaltimesecs`, `num_sections`, `url_iarchive`, and `sections[]`
  with `section_number`, `title`, `playtime` (seconds, as a string) and `listen_url` (an
  archive.org MP3).
- The JSON has no file sizes. archive.org's item metadata
  (`https://archive.org/metadata/<identifier>`, where the identifier is the last part of
  `url_iarchive`) lists every file with its size, and lists cover images too. Use it for the
  download size and the artwork.
- The API's `playtime` values are approximate. The builder decides whether to trust them for
  chapter `startTime`s, or to correct them from the real file durations once each file is
  downloaded (keeping the saved position consistent if they change).
- Popular/recent listing for the empty-query state: the builder picks the API parameters, for
  example the default feed order or `since=`.

## What's left to the builder

- The data model for multi-file books: how to represent per-chapter file URLs, remote URLs and
  download state in `AudioModel`/Core Data, and what the stable identity URL for a LibriVox book
  is. This must satisfy the identity and position constraints above.
- How the player moves between files: `AVQueuePlayer`, swapping `AVPlayerItem`s, or something
  else, as long as playback is seamless and chapter skip, seek, and saving and restoring position
  work across file boundaries.
- The download API's exact shape in NetworkProvider, and how Abbay's download queue is built on
  top of it.
- Where downloaded files live (the app's own storage, excluded from iCloud backup if sensible;
  no security-scoped bookmarks needed).
- How Wi-Fi vs cellular is detected (`NWPathMonitor`, `allowsCellularAccess`, or both).
- Localization strings, following the existing `Localizable` pattern.
- Test coverage at the level the repo already has (unit tests for use cases and the player;
  NetworkProvider's own tests; UI tests where the existing harness allows). Remember the memory
  rule: any committed audio fixture must be a small public-domain LibriVox recording, with its
  source recorded.
