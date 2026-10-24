# Notices (the error banner)

The app's one way of telling the user something failed (#115). Producers report a `Notice` to
`NoticeCenter`; `NoticeBannerView`, an overlay at the top of `AppRootView`, shows the current one
as a small card that slides in and dismisses itself. Before this, every failure below was a
`print` and the user saw nothing happen.

## Sub-features

- **mechanism:** `NoticeReporting.report(_:)` is safe from any thread (it hops to main).
  `NoticeCenter.shared` is the app's instance; the player, the library model and `DataStack` take
  it as an injectable default, so tests pass a `MockNoticeReporter`.
- **one at a time:** a new notice replaces the shown one. Reporting the notice already shown only
  restarts its timer, so a failure that fires twice (an item's status and its failed-to-end
  notification) is shown and announced once.
- **auto-dismiss:** 5 s, or 10 s while VoiceOver runs. There is no close button.
- **placement:** at the top, inside the safe area, above the tabs **and** the details screen, so
  it never covers the mini player or the tab bar. It does not take touches (`allowsHitTesting(false)`):
  taps go through to the toolbar or the player header underneath.
- **accessibility:** posted as a high-priority VoiceOver announcement. The banner is one element
  (label = the message) with a *Dismiss* action.
- **logging:** each reporting call site also logs through `Log` (`os.Logger`, categories
  `Player`, `Import`, `CoreData`): file names and titles `.private`, counts, flags and error
  domain/code `.public`.

### What reports what

| Failure | Notice | Message (en) |
|---|---|---|
| Import: some picked files didn't load (missing, no access, not playable audio) | `importFailed(fileNames:)` | *Couldn't import "X.mp3".* / *Couldn't import 2 files: A.mp3 and B.m4b.* (three names, then *N more*) |
| Play: an imported file is no longer there (moved, renamed or deleted, so the bookmark can't find it) | `fileMissing(title:)` | *"Title" was moved or renamed. Import it again to keep listening.* |
| Play: no URL, or the file is there but won't play | `playbackFailed` | *Couldn't play this book.* |
| Play: the audio session won't activate | `audioUnavailable` | *Audio isn't available right now. Try again in a moment.* |
| LibriVox: the current chapter isn't downloaded and the device is offline (#130) | `streamingOffline` | *You're offline and this chapter isn't downloaded. Download the book to listen without a connection.* |
| LibriVox: the current chapter failed otherwise | `chapterFailed` | *Couldn't play this chapter. Try again in a moment.* |
| Core Data: `DataStack.saveContext` threw | `saveFailed` | *Couldn't save your changes. Your latest progress may be lost.* |

The item failures come from observing the `AVPlayerItem` (status `.failed`, and
`AVPlayerItemFailedToPlayToEndTime` for a single file). For LibriVox only the chapter being played
counts: the queued next chapter failing ahead of time is reported once it becomes current. Play
again after a failure retries with a fresh item, so a persisting failure is reported again.

A failed item also **pauses the player** (`Player.stopAfterFailure`). Without that the
`AVQueuePlayer` kept its rate, reported itself as playing with no item, and the bar and row
showed *Pause*, so the first tap only paused. Now they show *Play*, and one tap retries.

| Also reported | Notice | |
|---|---|---|
| LibriVox details: *Download* when saving the book throws | `saveFailed` | *Couldn't save your changes…* (before, the button did nothing) |

## How to get to it (user POV)

- Import a file that isn't audio, or one that has gone from Files before the import finishes.
- Move or rename an imported book in Files, then press Play on it.
- Turn on Airplane Mode and press Play on a LibriVox book whose current chapter isn't downloaded.

## Driving it with abbay-ctl

```bash
$B launch --reset-library --stub-failing-import      # -resetLibrary -stubFailingImport
$B tap library.empty.import && $B wait notice.banner  # "Couldn't import 2 files: Missing Book.mp3 and Broken Book.m4b."
$B launch --seed-library
$B tap library.row.0.play && $B wait notice.banner    # seeded files don't exist: "... was moved or renamed ..."
```

`-stubFailingImport` makes *Import file* (`library.menu.import` and `library.empty.import`) skip
the system picker and import two files that don't exist, through the real `FileLoader`.

**Verified** (`NoticeUITests`): `notice.banner` after a failed import (label names the files, and
it goes away by itself) and after pressing Play on a seeded book (the seeded files don't exist,
so this is the moved-file notice). After the failure the row and the bar read *Play*, and one
tap on the bar's Play retries and shows the banner again
(`test_afterABookFailsToPlay_theButtonsShowPlay_andOneTapRetries`).

**Unit tests only:** `audioUnavailable` (the simulator's session always activates),
`streamingOffline` / `chapterFailed` (`PlayerNoticeTests`, with a fake network path and chapter
files that don't exist), `saveFailed` (`DataStackTests`, an in-memory store with its store
removed), and the VoiceOver announcement.

## Gotchas

- **Every seeded-book Play now shows the moved-file banner**, and Play on the stub LibriVox book
  shows *Couldn't play this chapter* (its chapter is `/dev/null`). The banner doesn't take
  touches, so other UI tests are unaffected, but it is in screenshots taken in the first 5 s.
- The banner sits over the navigation bar while shown; it never moves content.
- `fileMissing` vs `playbackFailed` is decided by `checkResourceIsReachable()` on the book's URL
  at the time of the failure.
- Logged only, not reported (pass 2 of #115): bookmark creation and resolution
  (`Log.bookmarks`; a dead bookmark surfaces as `fileMissing` on Play), Core Data fetches
  (`Log.data`), the import's save (`Log.importing`; `DataStack` already reports a failed save),
  chapter download failures and retries (`Log.downloads`; the row shows *Failed · Retry*), launch
  audio-session activation (`Log.player`; Play reports it, Settings shows the status) and Now
  Playing updates (`Log.nowPlaying`, debug level). `CatalogCache` still ignores read and write
  failures by design: it only saves time.
- No `os_log` or `print` is left in `Abbay/` or `AbbayIntents/`: the Siri extension,
  `LibrarySnapshotWriter` and `AppGroup` log through `Log` too (#87). `SiriDiagnostics` stays a
  separate App Group trail.
