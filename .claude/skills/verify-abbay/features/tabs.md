# Tabs and the two searches

`AppRootView` shows two tabs, **Library** and **Search**, each with its own `NavigationStack`. Each
tab has its own search: the Library's is local only, and the Search tab's queries LibriVox. Both
fields sit at the top of the screen on every iOS version. The [mini player](mini-player.md) docks
above the tab bar on both tabs.

## Sub-features

- **tab-bar (iOS 26.1+):** the system `TabView` with two regular `Tab`s (Library `books.vertical`,
  Search `magnifyingglass`), tinted malachite. It is **not** `Tab(role: .search)`: that role moves
  the Search tab's field into the bottom tab bar, and the owner wants it at the top (Ruling 10).
  The mini player is the tab bar's `.tabViewBottomAccessory(isEnabled:)`, which needs 26.1, hence
  the version split (Ruling 7). SwiftUI can't set ids on system tab items, so a small UIKit probe
  sets `root.tab.library` / `root.tab.search` on the `UITabBar` items.
- **tab-bar (iOS 17.0–26.0):** the hand-built `RootTabs`: a `background2` bar with the same two
  items (malachite when selected) and the docked mini player right above it. The pages end where
  the mini player starts: they are stacked above it, not inset, because a `List` in a tab's
  `NavigationStack` ignored a safe-area inset on iOS 18. Both tabs stay alive once visited (scroll
  position, query and pushed page kept). The Search tab is built on its first visit, so launch
  doesn't load Popular.
- **tab-bar-hidden-while-open:** the tab bar (either kind) is hidden only once the details screen
  has settled open, and shown again as soon as a close or a drag starts (Ruling 6).
- **keyboard:** typing doesn't lift the tab bar above the keyboard. The system bar stays under it,
  and the hand-built bar does too (`.ignoresSafeArea(.keyboard, edges: .bottom)` on `RootTabs`).
  Each tab's pages still avoid the keyboard
  (`test_typing_doesNotLiftTheTabBarAboveTheKeyboard`).
- **library-search:** the Library tab's
  `.searchable(placement: .navigationBarDrawer(displayMode: .always))`, prompt *Search your
  library* (`librarySearchPrompt`). It filters title or author through `LibraryFilter`, ignoring
  case and diacritics, and never touches the network. No matches shows `library.search.noResults`.
  There is no field while the library is empty. See [library](library.md).
- **librivox-search:** the Search tab (`LibriVoxSearchView`, title *Search*), same placement, prompt
  *Search LibriVox* (`librivoxSearchPrompt`).
  - **Empty query:** *Popular on LibriVox* as a grid of cards (`search.card.<n>`).
  - **Typed query:** a debounced LibriVox search whose results are `search.result.<n>`.
  - **No matches:** *No results* (`search.noResults`).
  - **Offline or failed:** a message (`search.message`): *You are offline…* or *Could not reach
    LibriVox…*.
  - Covers on cards and results shimmer while they load, then fade in; a failed one is an `onyx`
    tile with a book glyph. Loaded covers are cached in memory, so scrolling back or switching
    tabs doesn't shimmer them again. Same view as the details page (see its *cover-loading*).
    Cards and results keep their own ids (`search.card.<n>` still resolves); `cover.*` is only
    verified on the details page.
  - Tapping a card or a result pushes the [details page](librivox-details.md).
  - Clearing the query goes back to Popular without a spinner. Popular is refreshed in place.
- **browse-from-library:** *Browse free audiobooks* on the empty library (`library.empty.browse`)
  switches to the Search tab.

## Task 1 verdict (spike)

`ACCESSORY_HOSTS_EXPANSION = yes`
(`docs/superpowers/research/2026-10-23-tab-accessory-spike.md`): on iOS 26 the mini player can be the
tab bar's bottom accessory, and an overlay above the `TabView` can grow from the accessory's frame
under the finger. The condition is that nothing re-evaluating the view that builds the accessory may
change during the drag. That is why the root body reads only the selected tab, and why the
accessory's enablement lives in its own modifier (`MiniPlayerAccessory`).

## How to get to it (user POV)

Launch: the Library tab is selected. Tap **Search** in the tab bar for LibriVox.

## Driving it with abbay-ctl

```bash
$B launch --seed-library --stub-librivox
$B tap root.tab.search && $B wait search.card.0     # the stub's Popular is its one book
$B tap searchfield && $B type "Stub" && $B wait search.result.0
$B tap search.result.0 && $B wait detail.view
$B tap root.tab.library && $B wait library.list
```

**Verified** (`AccessibilityIdentifierTests`): `root.tab.library`, `root.tab.search`
(`test_tabs_switchBetweenLibraryAndSearch`), `search.card.0`
(`test_searchTab_showsPopularCards_andOpensDetails`,
`test_emptyLibrary_browseButton_opensSearchTab`), `search.result.0` (the stub book, typed
"Stub"), `library.search.noResults`. The fields' top placement (`test_searchTab_fieldIsAtTheTop`)
and the keyboard behaviour are tested on both iOS 26.4 and 18.5.

**Implemented but unverified:** `search.noResults` and `search.message`. No UI test types a
non-matching LibriVox query, and the stub client never fails or goes offline. Their states are
unit-tested in `LibriVoxSearchViewModelTests`.

**Not addressable:** the search fields have no identifier. Find each by placeholder: *Search your
library* or *Search LibriVox* (`app.searchFields` matching `placeholderValue`).

## Gotchas

- **Two code paths.** iOS 26.1+ uses the system tab bar and accessory. iOS 17.0–26.0 uses
  `RootTabs` and `MiniPlayerDock`. iOS 26.0 is on the hand-built path. Verify a change on both
  (26.4 and 18.5 simulators).
- **The tab ids on 26.1+ come from a UIKit probe** that walks the window after a tab switch and
  re-applies on a 0.6 s timer. It matches items by title, so the ids are fragile. Wait for them
  rather than reading them right after launch.
- With the accessory attached (26.1+), the accessibility tree reports the keyboard just off screen
  (minY = screen height) while it is visibly up. The keyboard UI test falls back to 65% of the
  screen height.
- Search needs `-stubLibriVox`. Without it, Popular and every query go to archive.org and
  librivox.org.
