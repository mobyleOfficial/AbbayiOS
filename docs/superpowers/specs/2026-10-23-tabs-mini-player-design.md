# Tabs, split search and a Spotify-style mini player: design

**Date:** 2026-10-23
**Status:** Approved by Edson (2026-10-23)
**Branch:** `feat/tabs-mini-player` (from `develop` at `499ebe8`)
**Mockups:** `.superpowers/brainstorm/81990-1792806422/content/spotify-compare.html` (the middle and right phones were chosen)

## Why

The bottom of the Library screen is crowded and looks wrong. On the owner's iPhone, the floating search field (iOS 26 puts `.searchable` at the bottom on iPhone) sits over the last book row and the bottom of the mini player.

The mini player is a tall card: cover, title, progress bar, two timestamps, four seek buttons (−30/−15/play/+15/+30) and a chapter counter. The owner wants it simpler, like Spotify:
- one docked row that never covers content
- search in its own place
- a player that grows out of the bar, following the finger

The owner uses the mini player for play/pause, skipping (sometimes to the next chapter or back to the chapter start), and opening the details screen.

## Goals

1. **Two tabs**, **Library** and **Search**, in a bottom tab bar, as in Spotify.
2. **Library search filters only the books already in the library**: imported files plus added LibriVox books, downloaded or not. It never hits the network. It replaces today's combined search, so the "On LibriVox" section leaves the Library.
3. **The Search tab is LibriVox-only.**
   - With an empty field it shows **Popular on LibriVox as cards** (cover tiles with the title).
   - Typing searches LibriVox, using the existing `LibrarySearchViewModel` logic for archive.org search, the cache, offline, debounce and generation guards.
   - Tapping a card or a result opens the existing `LibriVoxDetailView`.
4. **A one-row mini player docked above the tab bar** that never covers content:
   - cover, title, a subtitle such as "Chapter 35 · 12 min left", and play/pause
   - a thin progress line along its bottom edge for progress within the current chapter
   - a background tinted from the cover
5. **Mini player gestures:**
   - **Tap:** opens the details screen (today's `PlayerView`).
   - **Drag up:** expands it interactively. The details screen grows out of the bar and tracks the finger continuously, so a slow drag animates slowly. On release it settles open or closed, based on the drag distance and velocity.
   - **Swipe left:** next chapter. **Swipe right:** chapter start. Horizontal swipes must not conflict with the vertical drag.
6. **Collapsing is the mirror of expanding:** dragging the details screen down shrinks it back into the bar, also tracking the finger.

7. **Clean up the player subscriptions (owner request).** The previous design left many overlapping subscriptions. Today (`develop` at `499ebe8`):
   - **Every Library row** (`MediaViewModel`) builds its own `PlayerObserver` with a play-URL subscription. The playing row adds a 1 s time subscription. N rows give N+ subscriptions to one player.
   - **`FloatingPlayerView` forces a rebuild with `.id(UUID())`** (`FloatingPlayerView.swift:19`), so every re-render creates a new `FloatingPlayerViewModel`, `PlayerObserver` and subscriptions.
   - **`PlayerViewModel` and `MediaListViewModel`** each add their own observer and subscriptions.
   - **Download states:** `BookDownloadManager.statesPublisher` is sunk separately by every row, `PlayerViewModel`, `LibriVoxDetailViewModel`, and `MediaListView` (`onReceive`).

   **Hard rule, kept from the previous optimization (owner):** rows that aren't playing do **zero work per tick**. The player ticks every second. An earlier version had every row subscribed to it, so every row re-evaluated once a second and the app lagged. Today's design avoids that by giving only the playing row a time subscription. The cleanup must keep that property, not trade it for "one shared object everyone observes".

   **Target:**
   - **Split the slow state from the ticking clock.** One app-wide source subscribes to the player **once** and feeds two observable objects:
     - `PlaybackState`: `loadedBook` and `isPlaying`. It changes only on play, pause or switching books. Rows read this, and only this.
     - `PlaybackClock`: `bookTime` and `currentChapter`, updated about once a second. It's read **only** by the mini bar, the open details screen, and the playing row's small progress sub-view (shown only when that row's book is the loaded one).
   - **Use the Observation framework (`@Observable`, iOS 17)**, not `ObservableObject`. SwiftUI then re-renders a view only when a property that view read changes. With `ObservableObject`, any `@Published` change invalidates every observer, which reproduces the old lag. If a type must stay `ObservableObject`, keep the clock in its own object that only those three views hold.
   - **Rows hold no player subscriptions.** A row compares its book's URL with `PlaybackState.loadedBook`. This also removes the class of bug fixed in #116, where rows missed a play event.
   - **One download-state source**, keyed by book, read the same way. A row reads only its own book's entry, so one book's progress doesn't re-render the others: use an `@Observable` per-book entry, or an equivalent.
   - **No `.id(UUID())` rebuilds.** View models live as long as the thing they show.
   - **Remove what becomes unused:** per-view `PlayerObserver`s, `subscribeTo…` calls in view models, dead paths, and their mocks and tests. CarPlay keeps its own observer for now (CarPlay is a non-goal); the PR notes it as the one remaining consumer.

   **Acceptance (unit tests are the proof):**
   - **Subscription count:** with a counting mock player, subscriptions to the player's publishers stay **constant (≤ 2: URL and time)**, regardless of how many rows exist, re-renders, opening or closing the details screen, or switching tabs. Same for `statesPublisher`: one subscriber, the app-wide source.
   - **No per-tick work for idle rows:** `withObservationTracking` over everything a non-playing row reads, then advance `PlaybackClock` by a tick. The `onChange` must **not** fire. Over the playing row's progress sub-view, it **must** fire. Same idea for downloads: one book's progress must not notify another book's row.

## Non-goals

- Redesigning the details screen (`PlayerView`) itself: its cover, controls and the shared `ChapterListView` stay as they are. Only its presentation changes.
- CarPlay, Now Playing, Siri: unchanged.
- Settings (⚙️ stays a no-op, #58).
- A Home tab or recommendations beyond Popular on LibriVox.

## Anti-goals

- **Raising the minimum iOS.** The deployment target stays **iOS 17** (owner rule).
- **A janky or jumpy transition:**
  - The expansion must follow the finger with no snap at the start.
  - Cancelling a drag halfway must return smoothly.
  - The playing state and current time must never flicker or reset during the transition.
- **Regressions:**
  - Library row tap/play, the download ring, imported books, LibriVox download states, the "Downloaded" tag, and the cellular alert must behave as today.
  - The row fix from #116 (rows created after their book loaded show playing) must keep working.
- **The mini player covering list content**, or the tab bar covering the last row. Scroll insets must account for both.

## Constraints

- SwiftUI, iOS 17+, Swift 5 mode, XcodeGen. No third-party dependencies.
- **Colors:** only from `ColorConstants`, accent malachite, never `maximumRed`. The cover tint is derived from the artwork (e.g. a dominant or average color, darkened for contrast, so white text stays readable). Fall back to `onyx` when there's no artwork.
- **Strings:** new user-facing strings go in `Localizable` (en + pt-BR) and `LocalizationTests`.
- **Accessibility:**
  - Every tappable element gets an `AccessibilityID`, following the leaf-only rule in `.claude/skills/verify-abbay/features/README.md`.
  - The mini player needs a VoiceOver action to open the details, plus the swipe actions (next chapter, chapter start) as accessibility actions, because gestures aren't accessible.
- **Reduce Motion:** when enabled, replace the growing transition with a simple cross-fade or slide, keeping the same end states.
- **Existing logic to reuse:**
  - `FloatingPlayerViewModel` (play/pause, time subscription)
  - `PlayerViewModel` / `PlayerView`
  - `LibrarySearchViewModel` (LibriVox search, popular, cache)
  - `MediaListViewModel` (library, import, delete)
  - `Player.skipToNextChapter()`; chapter start is `PlayerProtocol.playChapter(at: currentChapter)` or an equivalent seek
- **Tests:** keep the unit and UI suites green. Update the UI tests and the feature map (`.claude/skills/verify-abbay/features/`) for the new structure: the tabs, both searches, and the mini player's ids and gestures.

## Decided by the owner

- Two tabs: Library and Search, as in the middle and right mockups.
- iOS 26 keeps the system Liquid Glass tab bar (native; spike the accessory first). iOS 17–25 get a hand-built equivalent.
- Library search is a local-only filter. The Search tab is a dedicated LibriVox search with popular cards.
- The one-row mini player is docked above the tabs.
- **Tap** on the mini player opens the details screen. **Drag** expands it interactively, with a slow drag giving a slow transition.

## Controller calls (my defaults; the owner can override)

- **Library search placement:** at the **top** of the Library (see "Settled after the builder check"). It filters title and author, ignoring case and diacritics, as today's local filter does. "No matches" keeps its own state.
- **Library toolbar:** ＋ and ⚙️ stay there. ＋ keeps only **Import file**, since the Search tab replaces "Browse LibriVox". The empty Library's primary button ("Browse free audiobooks") switches to the Search tab.
- **Tabs:** names "Library" (books icon) and "Search" (magnifying glass), with malachite selected.
  - **iOS 26:** use the system `TabView` with `Tab(role: .search)` and put the mini player in `.tabViewBottomAccessory`, if that allows the custom interactive expansion (see Builder questions).
  - **iOS 17–25:** draw an equivalent tab bar and docked bar in SwiftUI.
- **Search tab and owned books:** an owned book still appears in Search. Its details page shows Play, as today.
- **Mini player visibility:** shown on both tabs whenever a book is loaded in the player (today: whenever `selectedAudio` is set). Hidden while the details screen is fully open.
- **Library rows** are simplified to one line of detail: author, plus chapter N/M or time left. The two big counter blocks go. The row keeps its play button and download ring. The owner can drop this from scope.
- **Other ways to open details:** tapping a Library row and the details page's Play also open the details screen with the same expanding presentation, growing from the mini player's position, rather than a sheet. One way to present the player.
- **Settling thresholds:** open if released past about 30% of the travel, or flicked up faster than about 800 pt/s. Otherwise close. The same thresholds apply in reverse when collapsing.

## Settled after the builder check (controller calls)

- **One state owner above the tabs.** Move `MediaListViewModel` (library, `selectedAudio`, add/import/delete) and the player presentation state to a root view that owns the `TabView`. Both tabs use it; the Search tab adds books through it. `LibriVoxDetailView` stops presenting its own `.sheet { PlayerView }` and asks the root to open the player.
- **One player view model per presented book, not rebuilt** (superseded in part by goal 7: the shared `PlaybackState` is the single source; view models only adapt it). Today `FloatingPlayerViewFactory` rebuilds its model with `.id(UUID())`, and `PlayerView` creates its own `@StateObject`. Replace both with view models owned by the root (or keyed by book URL), so the bar and the details screen read the same state and nothing resets mid-transition. This refactors internals only; what the details screen shows doesn't change.
- **Which book each surface shows:**
  - The **bar** always shows the book **loaded in the player** (`selectedAudio`).
  - The **details screen** shows the **presented book**. Opened from the bar, that's the loaded book.
  - Tapping a Library row for a **different** book opens that book's details. It grows from the bottom edge, where the bar sits, with the same expanding presentation but driven by an animation instead of a finger. It doesn't start playback; pressing Play there loads it, and the bar switches to it.
  - If nothing is loaded, there's no bar, and row taps open details the same way, from the bottom edge.
- **During expansion the tab bar slides down out of view and the bar grows into the details screen.** Collapsing reverses this. Each tab's content uses a bottom safe-area inset of the bar's height plus the tab bar's, so nothing is covered.
- **Chapter swipes:**
  - **Left:** `skipToNextChapter()`. On the last chapter it does nothing, with a light haptic.
  - **Right:** restart the current chapter (seek to its `startTime`), as the owner described ("return to the beginning of the chapter"). It doesn't go to the previous chapter.
  - Books with no chapter metadata do nothing, with a haptic.
  - A LibriVox chapter that isn't downloaded streams, as playback already does.
  - The bar's text slides briefly in the swipe's direction as feedback.
- **Library search field:** always visible at the top of the Library (`.searchable(placement: .navigationBarDrawer(displayMode: .always))`), never at the bottom. Those placements are the reported bug.
- **Cover tint:** computed once per book from its artwork (a downscaled average, darkened until white text passes 4.5:1 contrast), cached by book URL, and recomputed when the bar's book changes. Text on the bar is always white. With no artwork, the background is `onyx`.

## Builder questions to answer in the plan (left to the builder)

- **Tab bar on iOS 26 (owner decision): native Liquid Glass, spike first.**
  - On iOS 26, use the system `TabView` with its Liquid Glass tab bar. First, spike whether `.tabViewBottomAccessory` can host the finger-tracked expansion.
  - **If it can,** the mini player lives in that accessory.
  - **If it can't,** keep the native glass tab bar anyway, and draw only the mini player and its expansion ourselves, docked above it.
  - **iOS 17–25** use the hand-built tab bar and bar.
  - Two code paths are accepted. Record the spike's result in the plan or PR.
- **Transition technique:** for example, a single overlay whose frame, corner radius, cover size and content opacity interpolate on a 0…1 progress value driven by the drag; or `matchedGeometryEffect` with an interactive progress. It must be interruptible: grabbing mid-settle continues from the current progress.
- **Gesture disambiguation:**
  - vertical drag (expand) vs horizontal swipe (chapters) on the bar
  - vertical drag (collapse) vs scrolling the chapter list inside the details screen. Collapse only when the list is scrolled to the top, or from the header and grabber area.
- **How the cover tint is computed** (e.g. averaging a downscaled image), and caching it per book.
- **Tests:** unit-test the gesture-to-progress mapping and the settle decision as pure functions; UI tests for tap-to-open, tab switching, both searches, and the mini player's ids.
