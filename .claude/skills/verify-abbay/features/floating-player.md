# Floating player

`FloatingPlayerView` — the mini player docked over the bottom of the library whenever something is
loaded. Same controls as the full player, smaller.

## Sub-features

- **presence:** rendered only when `MediaListViewModel.selectedAudio` is non-nil. That is driven by
  the player's URL publisher, so it appears for playback started from **any** source — the row's
  play button, the full player, Siri, or CarPlay.
- **transport:** the same five controls as [player](player.md), at 24pt.
- **scrubbing:** its own `PlayerProgressView` over the same bindings.
- **chapter-count:** `ChapterCountView` to the right of the transport row.
- **tap-through:** tapping the body sets `tappedAudio` and opens the full player sheet.
- **over-search:** it is part of `searchableContent`, so it stays docked over search results too, not only
  over the plain list. After Play on a details page, backing out to search still shows it
  (`test_search_showsFloatingPlayerAfterPlayingFromDetail`).

## How to get to it (user POV)

Start playing anything, then look at the bottom of the library. It persists across navigation
within the library and survives the full player being dismissed.

## Driving it with abbay-ctl

```bash
$B tap library.row.0.play                     # real audio only; a seeded book cannot play
$B wait library.floatingPlayer
$B tap library.floatingPlayer.transport.forward30
$B snapshot | jq '.elements[] | select(.id|startswith("library.floatingPlayer"))'
$B tap library.floatingPlayer                 # → full player sheet
# Presence after an external trigger (the Siri substitute path):
$B appgroup get abbay.lastPlayedAudioURL
```

**Verified** (`AccessibilityIdentifierTests`): `library.floatingPlayer`, resolved in search after
Play on the stub LibriVox book. It is applied to the whole floating player, so it is a **container**
id that overwrites anything inside it.

Identifiers to add: `library.floatingPlayer.{title,progress,chapterCount}`,
`library.floatingPlayer.transport.{back30,back15,play,forward15,forward30}` — which cannot coexist
with the container id above; move `library.floatingPlayer` off the container first, or the new leaves
will all read as `library.floatingPlayer`.

## Gotchas

- **`FloatingPlayerViewFactory.build` forces a new identity on every render** via `.id(UUID())`
  (`FloatingPlayerView.swift:19`). That discards and rebuilds the view model — and its player
  subscriptions — whenever the parent re-renders. Treat any state read from this view as freshly
  initialised, and do not rely on it accumulating.
- A LibriVox book's floating player shows book-wide time and chapter count like any other book; the
  stub book's `/dev/null` chapter means presence is provable, playback is not.
- It is the only user-visible confirmation that a Siri- or CarPlay-initiated playback actually
  started, which makes it the cheapest in-app assertion for those unreachable surfaces.
- It overlays the bottom of the list with `maxHeight: .infinity, alignment: .bottom`, so it can
  cover the last row. A driver tapping `library.row.<last>` may hit the floating player instead —
  scroll first, or address the row by identifier (Appium taps element centres, which still lands
  correctly when the element is only partly covered).
- Dismissing the full player does not dismiss this; only stopping playback removes it, and there is
  no stop control anywhere in the UI — `Player` has `pause()` and `cleanup()` but nothing user-facing
  clears `selectedAudio`.
