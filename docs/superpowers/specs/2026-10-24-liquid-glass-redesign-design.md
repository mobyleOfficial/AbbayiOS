# Liquid Glass redesign of the main screens: design

**Date:** 2026-10-24
**Status:** Approved by Edson (2026-10-24). One decision still open, tracked in #166.
**Tracking issue:** #166
**Branch:** `feat/liquid-glass-redesign` (from `develop` at `5896523`)
**Mockups:** `2026-10-24-liquid-glass-redesign-mockups/` next to this file. These are HTML sketches with placeholder gradient covers, not pixel specs.
- `redesign-v1.html`: chosen there were **Player A**, **Library B**, Search and Book page.
- `redesign-v2.html`: LibriVox book page with the glass chapter card. Its player "chapters in place" idea was **rejected**.
- `redesign-v3.html`: **the chosen player chapters UI**, a glass dropdown.

**Before screenshots** (develop at `e18a53b`, iOS 26.5 and 17.5): `AbbayiOS-redesign-recon/screenshots/`, a sibling of the repo and outside it.

## Why

Parts of the app look modern and parts look dated. The owner names these as modern:
- Settings
- the toolbar glass cluster (+ / gear) and its animations
- the tab bar
- the floating mini player

These look dated:
- the book details / player screen
- the library list ("Your Audiobooks")
- the LibriVox screens ("a bit wonky")

The owner wants the whole app to feel like Liquid Glass and Apple's own apps (Books, Music, Podcasts).

**Root cause, from the code audit.** The app makes no Liquid Glass calls of its own. A search for `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)` and `*Material` finds nothing in `Abbay/`. Everything that looks modern is plain system chrome that iOS 26 draws as glass. Everything that looks dated paints its own background over that chrome:
- `.backgroundColor(...)`, a ZStack fill (`View+Extensions.swift:30`)
- `onyx` panels
- `listRowBackground`
- fixed `.system(size:)` fonts
- hand-made button styles (`LibraryActionButtonStyle`, `DetailButtonStyle`, which are duplicates)

So the redesign is mostly **subtraction**: stop painting over the system and use text styles. **Addition** comes second: real glass on controls that float over content, and cover-tinted backgrounds.

## Goals

### G1. Player (today `PlayerView`, hosted in `PlayerExpansionOverlay`), "Player A"
- **Background:** a vertical gradient from the book's cover tint to near-black.
  - Use the same tint source as the mini player (`CoverTint`), so the bar-to-player expansion reads as one surface changing size.
  - Replaces the opaque `onyx` panel (`PlayerView.swift:52`, `PlayerExpansionOverlay.swift:102, 512`).
- **Header:**
  - Glass circular close button (⌄) on the left, grabber in the middle.
  - Glass ⋯ button on the right, only if there is something to put in it. **Builder's call** (see Left to the builder); omit it rather than ship an empty menu.
  - Replaces the hand-drawn chevron/grabber header (overlay :635-669).
  - `player.close` and the drag-to-collapse header behaviour stay.
- **Cover:** large (fills the width minus margins), corner radius ~14, a soft drop shadow.
  - Books without artwork get the generic artwork tile (G6), never the `photo` SF Symbol.
- **Title block:** left-aligned.
  - Title in `.title3.bold()` or similar text style.
  - Secondary line: author · "Ch N of M" (or just author for a book with no chapters).
  - The title no longer turns green while playing.
- **Scrubber:**
  - A thicker capsule track (~6 pt) with a white fill.
  - Under it: elapsed, **current chapter name** (centre, truncating), and remaining time.
  - Keeps the existing seek behaviour of `PlayerProgressView`. Restyle it, don't rewrite the gesture unless the builder finds it necessary.
  - Fix the deprecated one-argument `onChange` at :43 while there.
- **Transport:** skip back / play-pause / skip forward, larger than today. Play/pause is the dominant control.
  - Skip icons follow the Settings intervals as today: `gobackward.N` / `goforward.N`.
- **Bottom row:** two glass pills.
  - **Speed** (left), labelled with the speed ("1.25×"). Opens the existing speed sheet, `player.speed`.
  - **Chapters** (right). Hidden for a book with no chapters, where "No chapters" no longer needs a place on this screen.
    - That removes `player.chapters.empty`; update `EmptyStateUITests` and the feature map so the test checks the pill is absent instead.
    - `player.chapters.title` moves to the panel's "Chapters" header.
- **Book-level download progress** (`player.download.progress`, an incomplete LibriVox download): a thin progress line under the scrubber's labels, always visible while the download is incomplete, keeping its id. Per-chapter status stays in the panel.

### G2. Player chapters: a glass dropdown (`redesign-v3.html`)
Tapping **Chapters** morphs the pill into a **glass panel** that grows up from the button and floats over the cover. **Nothing else on the player moves.**
- **Panel:**
  - Rounded (~26 pt), anchored bottom-right above the Chapters pill.
  - Spans most of the width and is tall enough for roughly 8 rows; it scrolls.
  - A faint dim layer sits behind it.
- **Header row:** "Chapters" plus time left in the book.
- **Rows:**
  - number, title (wraps to 2 lines, never truncated into the duration column), duration as "1h 05m" / "42m"
  - **finished** chapters (before the current one) are dimmed, with a ✓ instead of a duration
  - the **current** chapter is malachite, with a ▶︎ marker, a thin progress bar under the title and "28m left"
- **Opening:** opens scrolled so the current chapter is visible.
- **Tapping a chapter** seeks to it and closes the panel. Whether that works while paused is decided under "Owner decisions" below.
- **Closing:** tapping outside, tapping the pill (shown as ✕ while open), Escape / the accessibility escape gesture, or dragging down on the panel while its list is scrolled to the top.
- **Collapse gesture:** the "drag down from the top of the chapter list collapses the player" path (`ExpansionListCollapse` / `ListCollapseModifier`) goes away, because the list no longer lives on the player. The player still collapses from its header and grabber exactly as today.
  - Delete the dead modifier and its iOS 18 gate.
  - Rewrite `MiniPlayerUITests` :284-325 to prove: the panel opens and scrolls to the current chapter, a drag at the panel's top closes only the panel, and the header drag still collapses the player.
  - Update the player and mini-player feature-map pages.
- **LibriVox download states:** per-chapter download status and "Failed · Retry" (`ChapterListView`, `player.chapter.N.retry`) must still appear in these rows.
- **Implementation:** (a popover is fine now that no collapse gesture has to pass through the panel) a `GlassEffectContainer` with `glassEffectID` morphing between the pill and the panel is the intended look. A popover on iOS 26 (which renders as glass) is an acceptable fallback if the morph fights the expansion overlay's gestures. **Builder's call**; record which one and why.

### G3. Library ("Your Audiobooks"), "Library B" (`redesign-v1.html`, right phone of section 2)
Large title, the existing glass toolbar cluster (+ / gear), and the search field at the top (`navigationBarDrawer(.always)`, unchanged). Then:

- **Continue card:**
  - Shows the last-played book (`LastPlayedStore.lastPlayedURL()`) if it is still in the library and not finished. Otherwise there is no card.
  - Content:
    - a rounded card with a cover-tinted gradient
    - cover (~94 pt), title (2 lines), "Ch 3 · 28 min left"
    - a malachite **Resume** capsule (or **Pause** if it is the playing book) and a progress bar
  - Tapping the card body opens the player. Resume/Pause toggles playback.
  - Hidden while the library search has text.
- **All books:** a section header followed by a **3-column grid of square covers**. Each cell has the cover, the title (fixed 2-line height so the grid stays even), and one status line:
  - "New", "Ch 14/135", "3h 20m left", or "Finished ✓"
  - a thin progress bar when started and not finished
  - the download ring (`downloadRing`) over the cover corner for LibriVox books that are downloading or not yet downloaded
  - while the library search has text, a fully downloaded LibriVox book keeps today's "Downloaded" tag (`DownloadedTag`), as a small badge on the cover corner so the cell height stays fixed
- **Tapping a cell** does what tapping a row does today: plays or opens per current behaviour. There is no separate play button per cell. **Builder:** check what today's row tap does versus the play button, and keep the same two actions reachable, with the cell tap plus a context-menu item if needed.
- **Context menu (long-press) on a cell:** Play/Pause, Delete (destructive, with today's delete semantics: `MediaListViewModel.deleteAudio`, removing files for LibriVox books). This **replaces swipe-to-delete**, which the owner accepted.
- **Order:** unchanged from today (repository order). The "Recent ⌄" sort shown in the mockup is **not** in scope (Non-goals).
- **Library search:**
  - results show in the same grid, without the Continue card
  - no matches shows the system `ContentUnavailableView.search`, keeping `library.search.noResults`
- **Empty library:** a `ContentUnavailableView` with the two existing actions, Browse free audiobooks and Import a file, as glass / glass-prominent buttons. Keep `library.empty`, `library.empty.browse` and `library.empty.import`. Delete `LibraryActionButtonStyle`.
- **Bottom of the scroll:** the last cell must clear the mini player and the tab bar, as today's last row does.
- **Drop** the `.backgroundColor()` wrapper and opaque list backgrounds so the scroll edge effect under the nav bar and the tab bar works.

### G4. Search tab (LibriVox browse), `redesign-v1.html` section 3, left phone
- **Fixed sizing:** covers are always square with the same corner radius, and titles sit in a fixed 2-line box, so nothing is ragged.
- **Popular** is the only browse data that exists today, so it shows as a **"Popular" section of square-cover cells in a uniform grid**.
  - The mockup's horizontal shelves only make sense with several sections. A "Em português" shelf is a follow-up (Non-goals).
  - **Builder's call:** grid vs single shelf. The grid is suggested while there is one section.
- **Results** use the same row style as the library's list rows used to: cover 48 pt, title, author · duration.
  - A glass **GET** capsule replaces the misleading `arrow.down.circle`. For a book already in the library, show **Open** or a ✓ instead.
  - Tapping the row or GET opens the book page, as today. GET does **not** start a download from the list.
  - **No duration on the line.** Search results don't carry one (`LibriVoxRequests.searchFields`, `totalSeconds: 0`), and fetching it would touch the API layer and `CatalogCache`. The line is the author only.
- **Idle, loading, offline, failed and no-results states** all use `ContentUnavailableView` or a centred `ProgressView`, instead of text padded 48 pt from the top. Keep `search.message` and `search.noResults`.
- **Drop** the `.backgroundColor()` wrapper and `listRowBackground`.

### G5. LibriVox book page (`LibriVoxDetailView`), `redesign-v1.html` and `redesign-v2.html`
- **Background:** the cover tint extends behind the top of the page and fades to the app background. Use `backgroundExtensionEffect()` on the cover or a gradient; **builder's call**.
- **Hero:** cover (~150 pt) centred with a shadow, then title and author centred.
- **Metadata line:** duration · N chapters · size.
  - **Fix:** size and number formatting follow the **app's** chosen language (`AbbayBundle.languageCode`), not the device locale, so the English UI shows "296.7 MB".
- **Primary action:** one full-width malachite **Download** button, `.buttonStyle(.glassProminent)` tinted malachite.
  - It becomes **Play** once downloaded. Progress shows while downloading.
  - Keep `detail.download`, `detail.play` and `detail.progress`.
  - Delete `DetailButtonStyle`.
- **Description:** secondary text with a malachite "more" (`detail.more`).
- **Chapters:** the **same glass card style as G2's rows**, inline on the page.
  - Numbered, titles wrap, durations as "1h 05m".
  - **One** glass rounded rectangle holding all the rows (the owner asked for the chapter list to match the glass style). The rows inside are not separate glass. That is a single layer, so it doesn't break the glass-on-glass anti-goal.
  - Per-chapter download state and "Failed · Retry" (`detail.chapter.N`, `detail.chapter.N.retry`) stay.
- **Pinned action:** once the big Download/Play button scrolls out of view, a compact glass Download/Play button appears in the navigation bar's trailing slot.
- **Fix:** nothing overlaps the system back button, and nothing slides under the status bar (both seen in the before screenshots).
- **Share button:** shown in the round-1 mockup, **dropped** (Non-goals).
- **Footer:** keep "Public domain recording by LibriVox volunteers".

### G6. Shared pieces (new, small)
- **`ArtworkView`**, or an extension of the existing `AsyncImageView`/`DataImageView`:
  - one component for every cover: corner radius by size, an 0.5 pt inner stroke, an optional shadow
  - a **generic artwork tile** (dark gradient with a `headphones` or `book.closed` glyph) for imported files without artwork and for load failures
  - replaces the white `photo` SF Symbol everywhere: library, player, mini player, search
- **Glass helpers in one file** (`View+Glass.swift`): e.g. `abbayGlass()`, `abbayGlassButton()`, `abbayGlassProminentButton()`.
  - On iOS 26 they call the real APIs.
  - On iOS 17–25 they fall back to the plain system look (`.bordered` / `.borderedProminent`, or `.regularMaterial`).
  - **This is the only file with `#available` checks for the redesign.** Screens call the helpers and never branch on the OS themselves.
- **Chapter row** shared by G2 and G5 (it already is, through `ChapterListView`). Restyle it there once.
- **Typography:** text styles (`.title3`, `.headline`, `.subheadline`, `.footnote`, `.caption`) replace `.system(size:)` on every screen this redesign touches, so Dynamic Type works.
- **Colours** still come only from `ColorConstants` (malachite accent, never `maximumRed` as an accent), plus white/black opacities for glass tints and separators.

### G7. Light polish of the parts the owner already likes
- **Settings:** remove `.scrollContentBackground(.hidden)`, `.background(background)` and `listRowBackground(onyx)` (`SettingsView.swift:41-42, 97, 149, 181, 214`) so the iOS 26 sheet shows its own grouped glass look. Check that it still reads well dark-only.
- **Speed sheet:** preset chips in one row, all the same size, as glass capsules. The rest is unchanged. Keep every `speed.*` id.
- **Mini player, tab bar, toolbar cluster:** **unchanged**, except the mini player's placeholder artwork becomes G6's generic tile.
- **Notice banner:** shown over the toolbar in the before screenshots. Make it a glass capsule with the red used only for its icon; **builder's call** on placement so it doesn't cover the toolbar.

## Non-goals
- **Light mode.** The app stays dark-only (`.preferredColorScheme(.dark)`). That's the owner's decision; light mode could be its own project later.
- **Raising the deployment target.** It stays iOS 17.0 (`CLAUDE.md`; research below). iOS 17–25 get the plain system look through G6's helpers, not a pixel match.
- **New features:**
  - library sort menu ("Recent ⌄")
  - extra Search shelves ("Em português")
  - share button
  - a sleep timer or AirPlay button on the player
- **Behaviour changes to playback, downloads, gestures and the mini player.** The expansion overlay's gestures, the docking and the spike gotchas (`docs/superpowers/research/2026-10-23-tab-accessory-spike.md`) are untouched. Only the overlay's **contents and background** change.
- **CarPlay, Siri, the app icon** (`feat/liquid-glass-icon` is separate work).

## Anti-goals (would be a failure even if it "works")
- **Glass on glass.** Glass is for controls floating over content: buttons, pills, the chapter panel, toolbars. Content (cells, chapter rows on a page) sits on a tinted fill or the background, not on stacked glass layers.
- **Breaking the bar-to-player expansion.** Any jank, a flash of the old `onyx` background, or the tint not matching between the bar and the player.
- **Truncated or overlapping text** at default and at the largest non-accessibility Dynamic Type size, in English and pt-BR.
- **OS checks scattered through the screens** instead of kept in the helpers file.
- **Losing an accessibility id** that a test or the feature map uses, or putting an id on a container (see the leaf rule in `AccessibilityID.swift`).

## Constraints
- **Repo working rules (`CLAUDE.md`):**
  - Branch from and PR into `develop`, squash-merged.
  - Feature-map pages updated in the same PR.
  - Live verification in a simulator.
  - Every gap filed as an issue.
  - Before/after screenshots on the `pr-screenshots` branch, including pt-BR.
  - `bundle exec fastlane verify` passes.
  - Every new string in `Localizable.xcstrings` with `en` and `pt-BR`.
- **Other agents are working in this repo.** Don't touch other worktrees or branches, and use dedicated simulators with `-parallel-testing-enabled NO`.
- **`Abbay.xcodeproj` is generated and gitignored.** Run XcodeGen in the worktree before building; a project generated before #143 fails to build (missing `KeyValueStore.swift` in AbbayIntents).
- **Minimum 26.0 for the glass APIs.** The mini player's accessory path already needs 26.1 and stays as it is.

## Deployment target research (why not iOS 26)
StatCounter, September 2026, page-view based:

| Minimum | Brazilian iPhones excluded |
|---|---|
| iOS 17 (today) | about 4.4% |
| iOS 18 | about 5.7%, with no device models lost |
| iOS 26 | about 21% |

- iOS 26 drops the XS, XS Max and XR. Most of the 21% are phones that could update but haven't.
- Going iOS 26.1-only would remove about 170–190 lines: `RootTabs.swift`, `MiniPlayerDock`, the `isAccessory` branches and `HiddenWhilePlayerIsOpen`.
- **Decision:** stay on 17. Revisit around mid-2027, when iOS 18's share should be about 8–10%, or sooner if App Store Connect analytics show the real audience is already on 26.

## Tests that change
- **Library UI tests** move from rows to grid cells (about 24 uses of `library.list` and 19 of `library.row.N.*`).
  - Keep the ids if they still make sense on a cell: `library.row.N.title`, `.detail`, `.artwork`, `.downloadRing`. **Builder's call** whether to rename to `library.cell.N`; update `AccessibilityID.swift`, the tests and the feature map together.
  - Add `library.continue`, `library.continue.resume` and `library.cell.N.menu` (or equivalents).
  - Delete moves from a trailing swipe to a context menu.
  - "Last row ends above the mini player" becomes "last cell ends above the mini player".
- **Player chapter tests** (`MiniPlayerUITests` :284-325, scroll then collapse from the top) get rewritten for the dropdown. Add `player.chapters` (the pill) and `player.chapters.panel` (on a leaf, per the leaf rule).
- **Unit tests** for the pure logic added:
  - Continue-card eligibility: last played, in the library, not finished.
  - Chapter row state: finished / current / upcoming.
  - Size formatting by app language.

## Owner decisions
- **Tapping a chapter while paused, or while the player shows a book that isn't loaded:** _still open, tracked in #166._ The recommendation is that a tap always seeks to the chapter and starts playback. It must be settled before the G1 + G2 PR.

## Calls made in writing this (not confirmed by the owner)
- Library order stays as it is today. The Continue card uses `LastPlayedStore`, which already exists, and no new "recently played" data.
- Search results show the author only, with no duration.
- On the LibriVox book page, the chapter card is one glass layer with plain rows inside.
- The "Downloaded" tag survives as a badge on the cover.
- The player's chapter list loses its drag-to-collapse path; the header drag stays.
- Book-level download progress sits under the scrubber.
- The share button, "Em português" shelf and sort menu from the mockups are left out.

## Left to the builder (sensible-default calls, not the owner's)
- Exact sizes, spacings and radii (the mockups are sketches).
- G2: glass morph vs popover.
- G1: whether the ⋯ button ships (only with real actions in it).
- G4: grid vs shelf for Popular.
- G5: `backgroundExtensionEffect` vs a gradient.
- Cell id naming.
- Where the notice banner sits.
- How the redesign is split into PRs: suggested order is G6 shared pieces → G1+G2 player → G3 library → G4+G5 LibriVox → G7 polish, each one PR into `develop`.
