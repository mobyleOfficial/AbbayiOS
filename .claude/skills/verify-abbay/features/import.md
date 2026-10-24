# Import

Adding an audiobook. The system document picker, metadata and chapter extraction, and the
security-scoped bookmark that makes the file playable again after relaunch.

## Sub-features

- **picker:** `DocumentPickerView` wraps `UIDocumentPickerViewController(forOpeningContentTypes:
  [UTType.audio], asCopy: false)`. Multi-select is delegate-driven; files are referenced **in
  place**, never copied into the sandbox.
- **metadata-extraction:** `FileLoader.load(urls:)` reads duration, title, album, artist and
  artwork from the asset, then chapter groups via `loadChapterMetadata`.
- **chapter-parsing:** `AVTimedMetadataGroup`s become `[ChapterModel]` (`title`, `startTime`,
  `duration`). A file with no chapter metadata yields an empty array, which disables every
  chapter feature for that book.
- **bookmark-creation:** `Player.play` lazily creates the security-scoped bookmark on first play,
  not at import (`Player.play`), writes it back through the update-only
  `SavePlaybackPositionUseCase`, and refreshes the snapshot. LibriVox `librivox://` books are never
  bookmarked: they are not files.
- **de-duplication:** `importAudio` appends only files whose `url` is not already in `audioList`.
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
  handles the stale case by recreating the bookmark, but all five branches there are `print`-only
  (12 `// TODO: Add logging` markers) — a failure is silent.
- The bookmark is created on first **play**, not on import. A book imported and never played has
  `bookmarkData == nil` in the snapshot, which is why `IntentRouter.resolveURL` falls back to the
  raw identifier string.
- A file with no embedded chapters silently disables next/previous chapter, the chapter list, and
  `PlayChapterIntent` for that book. The test fixture must have real chapters for this reason.
- `importAudio` is `@MainActor` and awaits metadata loading per file; a large multi-select blocks
  the picker dismissal.
