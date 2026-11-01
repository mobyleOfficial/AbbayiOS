# Import

Adding an audiobook. The system document picker, metadata and chapter extraction, and the
security-scoped bookmark that makes the file playable again after relaunch.

## Sub-features

- **picker:** SwiftUI's `.fileImporter` on the Library (`[UTType.audio]`, multiple selection):
  the system presents its own picker, a centred form sheet on a regular width. Files are referenced
  **in place**, never copied into the sandbox; `FileLoader` takes their security scope. Known: on
  iOS 27.1 the Files picker draws its first frame at phone width against the left edge before it
  fills its sheet (the unfolded iPhone Duo), however it is presented; full screen it does the same
  (#268).
- **metadata-extraction:** `FileLoader.load(urls:)` reads duration, title, album, artist and
  artwork from the asset, then chapter groups via `loadChapterMetadata`.
- **chapter-parsing:** `AVTimedMetadataGroup`s become `[ChapterModel]` (`title`, `startTime`,
  `duration`). A file with no chapter metadata yields an empty array, which disables every
  chapter feature for that book.
- **bookmark-creation:** `Player.play` lazily creates the security-scoped bookmark on first play,
  not at import (`Player.play`), writes it back through the update-only
  `SavePlaybackPositionUseCase`, and refreshes the snapshot. LibriVox `librivox://` books are never
  bookmarked: they are not files.
- **stale-bookmark-refresh:** loading a book (`LoadAudioUseCase`, `LoadAllAudiosUseCase`) resolves
  its bookmark with `URL.resolveBookmarkRefreshing(from:)`. When iOS reports it **stale**, a new
  bookmark is made and `StaleBookmarkSaver` saves it to the book's row through `SaveAudioUseCase`
  (under the row's stored URL, so no second row appears), once per book per launch; a library load
  saves all its stale books in one call (#146). Before, the new bookmark was made and dropped on
  every play. Unit-tested with a stubbed resolver (`StaleBookmarkTests`): a stale bookmark can't be
  made on demand, so this hasn't been seen on a device.
- **de-duplication:** a picked file whose URL is a stored book's row URL loads that book
  (`LoadAudioUseCase`) and is not saved again. In `audioList`, a loaded book whose `url` is already
  there replaces that row instead of adding one.
- **re-import of a moved book (#196):** a picked file at a new URL is checked against the library
  (`ReimportMatcher`, called by `FileLoader.load(urls:)`, which loads the library once per import and
  only on a miss). It is a book already there when (1) a stored book's `fileURL` is the same file
  (same path once symlinks are resolved, or the same file resource identifier, e.g. a hard link),
  or (2) the book is *lost* (imported, its file not reachable, which is the moved-file banner's
  case) and has the same duration (±1 s) and the same file name or the same non-empty title, and is
  the only lost book that fits. Then the book is **relinked**, not added: it keeps its identity
  (`url`), position, title and speed, gets the picked file's bookmark and `resolvedURL`, and is
  saved to its own row. UI-tested with `-stubMovedImport` + `-seedMissingFile`
  (`NoticeUITests.test_importingAMovedBooksFileAgain_relinksTheBook_insteadOfAddingASecond`);
  unit-tested by `ReimportMatcherTests` and `FileLoaderReimportTests` (real Core Data). No notice
  is shown: the row simply plays again.
- **failures:** `load(urls:)` returns a `FileImportResult` (`loaded`, `failed`). A file fails when it
  can't be opened or isn't playable audio (`AVURLAsset.isPlayable`), so a renamed text file is no
  longer an empty row. `importAudio` adds what loaded and reports the rest as one
  `importFailed(fileNames:)` notice (see [notices](notices.md)); UI-tested with `-stubFailingImport`.
- **debug imports:** UI tests can't drive the picker, so *Import file* imports
  `DebugOverrides.importURLs()` straight away when set: `-stubFailingImport` (two files that don't
  exist) or `-stubMovedImport` (*Seeded Missing Book*'s `missing.m4b`, a copy of the fixture at
  `Application Support/UITestSeedAudio/moved/`).
- **post-import publish:** writes `abbay.librarySnapshot.v1`; the write publishes to Siri
  (`SiriLibraryPublisher`), which refreshes the App Shortcut parameters once so Siri's entity
  suggestions pick the book up. The view model makes no direct refresh call of its own (#84).

## How to get to it (user POV)

Library → the ＋ toolbar menu → *Import file* (or *Import a file* on the empty library) → the Files picker → choose one or more
audio files → the picker dismisses and the rows appear.

## Driving it with abbay-ctl

```bash
# Preferred: skip the system picker entirely.
$B launch -seedLibrary                       # planned: import the bundled LibriVox fixture
$B launch -seedLibrary -seedMissingFile -stubMovedImport
$B tap library.toolbar.add && $B tap library.menu.import   # relinks Seeded Missing Book: still 3 rows
$B snapshot && $B appgroup get abbay.librarySnapshot.v1

# The one deliberately brittle path, run on its own and never as a precondition:
$B tap library.toolbar.add && $B tap library.menu.import   # or library.empty.import
$B files pick <name>                         # planned: drives com.apple.DocumentsApp out-of-process
```

Identifiers to add: `import.picker` (the sheet's container, for presence assertions only — the
picker's own contents are system-owned and carry no identifiers of ours).

## Gotchas

- **Do not make the system picker a precondition for anything.** It is hosted out of process,
  its layout varies by iOS version, and the practitioner consensus is that driving it is
  unreliable. Appium can `activateApp('com.apple.DocumentsApp')` and retarget lookups with
  `defaultActiveApplication`, but the known recipes are old and partly broken. Seed instead, and
  keep exactly one labelled brittle test for this path.
- The simulator's Files app has nothing to pick unless something put files there first. Abbay's
  `Info.plist` sets neither `UIFileSharingEnabled` nor `LSSupportsOpeningDocumentsInPlace`, so the
  app's own container is not browsable either.
- **`asCopy: false` is the whole risk surface.** The file stays where the user put it, so playback
  depends entirely on the security-scoped bookmark resolving later. `URL+SecurityScoped.swift`
  handles the stale case by recreating the bookmark, which is now saved (see
  *stale-bookmark-refresh*), and logs through `Log.bookmarks`.
- **identity (#176, #186):** a book is identified by the URL its row was saved under,
  `AudioModel.url`, and nothing else: row reads and writes, last played, the Siri snapshot's
  `urlString` (entity ids, donations, Spotlight), per-book speeds, CarPlay's playing row and the
  library's rows all key it by that. A bookmark that resolves to a new path sets
  `AudioModel.resolvedURL`; `fileURL` (`resolvedURL ?? url`) is used only to reach the file (the
  player item, its security scope, a new bookmark, the reachability check, a title-less book's
  name). So a moved book still plays, resumes from Siri, plays by name, keeps its speed, shows as
  playing in CarPlay and can be deleted. `MovedBookIdentityTests` (stubbed resolver, real Core
  Data) pins each.
- **key migration (#186):** before #186 the player saved a moved book's last-played pointer and
  speed under its resolved URL. `MovedBookKeyMigration` moves both to the row's URL the first time
  a load (`LoadAudioUseCase`, `LoadAllAudiosUseCase`) returns the book in a launch; a speed already
  under the row's URL wins. `IntentRouter` loads an identifier as is, and on a miss looks for the
  snapshot book whose bookmark resolves to it, so a donation from before #186 still plays.
- A bookmark that no longer resolves surfaces at Play: the item fails and the user sees
  *"Title" was moved or renamed. Import it again…* (see [notices](notices.md)). Importing it again
  relinks the book (*re-import of a moved book*), so its row plays from where it was.
- The lost-book match is a heuristic: a *different* file with the same duration and file name (or
  title), imported while the original's file is gone, relinks the old book rather than adding a new
  one. Two lost books that both fit match neither, and the file is added as a new book.
- The bookmark is created on first **play**, not on import. A book imported and never played has
  `bookmarkData == nil` in the snapshot; Siri still loads it by its identifier.
- A file with no embedded chapters silently disables next/previous chapter, the chapter list, and
  `PlayChapterIntent` for that book, until the experimental *Find chapters* finds them in its audio
  ([find-chapters](find-chapters.md)). The test fixture must have real chapters for this reason.
- `importAudio` is `@MainActor` and awaits metadata loading per file; a large multi-select blocks
  the picker dismissal.
