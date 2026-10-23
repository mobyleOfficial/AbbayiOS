# Siri — library publishing

Everything that teaches the system what Abbay's books are called, so a spoken title resolves. Not
user-facing, but every title-matching Siri phrase depends on it.

## Sub-features

- **publish-on-launch:** `AppDelegate` calls `SiriLibraryPublisher.publish(audios:)` on **every**
  launch (`didFinishLaunchingWithOptions`). Apple requires at least one successful entity fetch before
  entity-parameter phrases resolve at all, and the snapshot seeder only writes when the snapshot is
  missing, so launch cannot rely on the write path.
- **publish-on-mutation:** `LibrarySnapshotWriter.write` calls the publisher at the end, guarded out
  of the extension build. Every import and delete therefore refreshes Siri's view.
- **snapshot:** `abbay.librarySnapshot.v1` in the App Group — a versioned `LibrarySnapshot` of
  `{title, urlString, bookmarkData}`. The extension's only data source.
- **spotlight:** `LibrarySpotlightIndexer` indexes each book as a `CSSearchableItem` in a named index
  with `completeUntilFirstUserAuthentication` protection, so the system can read it while locked.
  Skips books with no URL or an empty title.
- **entity-queries:** `AudiobookEntityQuery` (40 suggestions) and `ChapterEntityQuery` (50) back the
  entity parameters. Both implement `EntityStringQuery` so Siri can match a spoken string.
  `ChapterEntity.currentBook()` resolves chapters against whatever is playing.
- **shortcut-parameter refresh:** `AbbayAppShortcuts.updateAppShortcutParameters()` after import, and
  after a LibriVox book is added (`MediaListViewModel.addLibriVoxBook`) or deleted.
- **media-affinity:** `MediaUserContextDonor` and `IntentDonor.donatePlayMedia` donate interactions
  so the system learns to prefer Abbay for audiobook requests.

## How to get to it (user POV)

Invisible. It manifests as whether *"Play \<title> in Abbay"* resolves at all, and whether Abbay
appears in Spotlight search for a book title.

## Driving it with abbay-ctl

```bash
$B launch --seed-library
$B appgroup get abbay.librarySnapshot.v1 | jq '.audios | length'
$B appgroup get abbay.librarySnapshot.v1 | jq '[.audios[] | select(.bookmarkData != null)] | length'
$B spotlight query "<title>"                  # planned: CSSearchQuery against our named index
```

`AppIntentsTesting` can validate entity queries and Spotlight indexing directly, which makes this
feature one of the better arguments for taking the Xcode 27 upgrade.

## Gotchas

- **Publishing on every launch is deliberate — do not "optimise" it away.** The comment at
  the comment in `didFinishLaunchingWithOptions` records why: without one successful entity fetch, entity phrases never
  resolve.
- **LibriVox books publish as ordinary entries, by assumption.** `addLibriVoxBook` rewrites the
  snapshot, so a downloaded book is in `abbay.librarySnapshot.v1` with its `librivox://book/<id>` as
  `urlString` and a null bookmark (the URL fallback in `IntentRouter.resolveURL` then loads it).
  The publishing, Spotlight and entity-query code is unchanged on this branch and no test builds a
  snapshot from a LibriVox model; resolution of "Play <title> in Abbay" for such a book is unverified.
- `bookmarkData` is written only when non-empty, and books are only bookmarked on first *play*. A
  freshly imported library publishes titles with null bookmarks, which still resolve via the URL
  fallback but are fragile if the file moves.
- `LibrarySnapshotWriter` logs through `os_log` with `%{public}` counts and a `LibrarySnapshot`
  category — useful, and notably the one place in the app that uses real logging rather than `print`.
- The Spotlight indexer returns early when *every* item is filtered out, so an all-untitled library
  silently indexes nothing.
- `SiriLibraryPublisher` is `static var shared` so tests can rebind it; the same is true of
  `LibrarySpotlightIndexer.shared` and `LibrarySnapshotWriter.shared`. Rebind in `setUp`, restore in
  `tearDown`, or tests leak into each other.
