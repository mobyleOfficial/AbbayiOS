# Adaptive layout

One interface for a regular iPhone, both iPhone Duo displays and a native iPad window (#255; spec
`docs/superpowers/specs/2026-10-27-adaptive-duo-ipad-design.md`). The layout follows the room the
app is given and the text size, never the device model.

## Sub-features

- **split-decision:** `AdaptiveLayout.decide` (`Abbay/View/Root/AdaptiveLayout.swift`) turns the root's
  measured size (inside the safe area), the horizontal size class and the Dynamic Type size into a
  `PaneLayout`: `.single`, or `.split(playerWidth:)`. A compact width is always one pane. A regular
  width is split when it is at least 500 pt tall and has room for both minimums: 360 pt of browsing
  and a 360 pt player. Both minimums grow ×1.15 from *xLarge* and ×1.4 at accessibility sizes. The
  player takes 42 % of the width, between 360 and 460 pt; the rest is browsing. `AdaptiveLayoutReader`
  (in `AppRootView.swift`) puts the decision in the environment (`\.paneLayout`) and calls
  `PlayerPresentation.layoutChanged(usesPanes:)` when the split changes.
  - The folded Duo (466 × 678 pt, compact) and any iPhone in portrait: one pane.
  - A large iPhone in landscape is regular width but too short: one pane.
  - The unfolded Duo (inner display, landscape) and a full iPad, portrait or landscape: split.
  - A narrow iPad window (Slide Over, a small Split View): one pane, like a phone.
- **states:** three states of one interface (the spec's C, A and B), kept in `PlayerPresentation`
  (`presentedBook`, `isShowingChapters`) so a fold, a rotation or a resize shows the same state in
  the other form.
  - **C, browsing:** Library or Search fills the window. The [mini player](mini-player.md) shows while
    a book is loaded.
  - **A, player open:** split, the player is a pane on browsing's trailing side (`BrowsingPanes`, hosted inside
    each tab so the system tab bar keeps its place: top on an iPad, a side strip on the Duo). In one
    pane, the full-screen player covers browsing, as before.
  - **B, chapters open:** split, the player slides to the leading side and the chapters
    (`ChaptersPanel` `.pane` style) take the trailing side, in browsing's room (#271, as the spec's
    mockup). Browsing stays alive underneath (hidden, not removed), so its scroll position,
    query and pushed LibriVox page are still there when the chapters close. Its navigation bar is
    hidden meanwhile (`HiddenNavigationBarWhileCovered`, `\.isBrowsingCovered`): at the window's
    trailing edge the system would otherwise show the hidden page's toolbar (`+`, gear) in the Duo's
    side strip. In one pane, the chapters
    are the glass panel over the player ([player](player.md) *chapter-panel*).
- **actions (split):**
  - A library cell, the Continue card body, or the mini player opens the player pane. There is no
    expansion: the pane slides in from the trailing edge (cross-fades under Reduce Motion).
  - The pane's ✕ (`player.close`, *Close player*) closes it at once, back to C.
  - The Chapters pill opens B. The chapters pane's ✕ (`player.chapters.panel`, *Close chapters*),
    or the pill (now *✕ Chapters*), closes it, back to A.
  - A chapter tap plays that chapter of the presented book, as in the panel, and **keeps** the pane open.
  - A tab switch while B is open closes the chapters: the chosen tab shows beside the player.
  - The mini player stays while the pane shows another book than the loaded one (a preview).
  - A drag up on the mini player opens the pane (nothing is dragged).
- **reflow:** `layoutChanged` ends any drag or spring and settles open if a book is presented.
  - Split → one pane: the full-screen player, with the compact chapter panel if B was open.
  - One pane → split: A, or B.
  - Browsing (C) never opens the player because there is more room.
  - Playback, the book, the speed and downloads are untouched. The player pane and the full-screen
    player share one `PlayerViewModel` (`PlayerDetailsModels`, owned by the root).
- **scroll-anchor (#267):** `MediaListView` follows the top visible book with `scrollPosition(id:)`.
  While the grid's width is changing (the player pane's spring, a fold), that value is frozen. Once
  the width has held still for 0.45 s (`LibraryGridLayout.resizeSettleDelay`), and if the column
  count changed, the book that was at the top scrolls back there. In the first row nothing moves,
  so the Continue card and the header stay in view (`LibraryGridLayout.restoresTopBook`).
- **library-columns:** `LibraryGridLayout.columnCount` fits the grid's own measured width:
  - Default text: covers of at least 104 pt. That is three columns on every phone in portrait, as
    before, two on the narrowest. Past a 600 pt grid, covers of at least 150 pt.
  - Larger text: ×1.4 from *xLarge* (two columns on a phone, as before) and ×1.5 at accessibility
    sizes.
  - The grid sits inside the safe area, so the folded Duo's side strip no longer cuts off its third
    column (#251).
- **side-insets:** the full-screen player pads its content and header by the window's leading and
  trailing safe-area insets. On the folded Duo the cover no longer runs under the status strip on
  the right. The cover tint still reaches the edges.
- **orientations-and-ipad:** the iPhone supports portrait and both landscapes (no upside-down), and
  `UIRequiresFullScreen` is gone, so the unfolded Duo's landscape inner display is used in full rather
  than as a centred phone column. `TARGETED_DEVICE_FAMILY` is `1,2` (`project.yml`; it used to
  misspell the setting `TARGET_DEVICE_FAMILY`, which Xcode ignored), so the app runs natively on an
  iPad, with every orientation and multitasking.

## How to get to it (user POV)

Unfold an iPhone Duo, or open the app on an iPad. The library fills the screen. Tap a book: its player
opens on the library's right. Tap **Chapters**: the player moves left and the chapters open on its right. Fold the Duo with
the player open: it becomes the full-screen player, with the chapter panel if the chapters were open.

## Driving it with abbay-ctl

Two simulators, since the Duo's fold can't be scripted (only DeviceHub folds it, #252): **iPhone Duo
(fold)** kept folded and **iPhone Duo (unfold)** kept unfolded, both iOS 27.1. On an unfolded Duo,
`XCUIScreen.main.screenshot()` and `app.screenshot()` return the dark outer display; capture with
`xcrun simctl io <udid> screenshot` (the inner display is the default one).

```bash
$B launch -seedLibrary -seedPlayableBook -seedArtwork -seedLastPlayed -seedFillerBooks
$B tap library.row.1.title && $B wait player.title     # split: the pane; one pane: the full-screen player
$B tap player.chapters && $B wait player.chapter.0    # split: B beside the player; one pane: the panel
$B tap player.chapter.1                               # split: plays it, the chapters stay
$B tap player.chapters.panel                          # closes the chapters (either form)
$B tap player.close                                   # back to browsing
```

Evidence: on a split window, `player.title`'s frame starts right of `library.list`'s (A), and the
chapter rows start right of `player.title` (B); on one pane the player covers them. `AdaptiveLayoutUITests` asserts this on whichever
simulator it runs, and writes screenshot requests when `TEST_RUNNER_ABBAY_SHOTS_DIR` is set (see the
test's `shot`).

## Gotchas

- The pane is hosted **inside** each tab, around its `NavigationStack`, not beside the `TabView`.
  Beside it, the system's tab bar (a side strip on the unfolded Duo) would sit between browsing and
  the player. Only the selected tab hosts it: the hand-built tabs keep the hidden tab alive, and its
  pane would tick for nothing.
- The mini player reads `presentedBook` only when split. In one pane, a drag up on the bar presents
  a book, and a bar that re-rendered then would lose its own gesture.
- `AdaptiveLayoutTests` pins the decisions (split, columns, the bar's visibility, the presentation
  across a split change).
