# Tabs, Split Search and Spotify-Style Mini Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single Library screen and its tall floating player with two tabs (Library, LibriVox Search), a one-row mini player docked above the tab bar that expands into the details screen under the finger, and one low-churn source of playback and download state.

**Architecture:** One `PlaybackCenter` subscribes to the player once. It feeds two `@Observable` objects:
- `PlaybackState`: loaded book and playing flag. Slow-changing; read by everyone.
- `PlaybackClock`: time and chapter. Ticks about once a second; read only by the mini bar, the open details screen, and the playing row's progress sub-view.

A `DownloadStateStore` does the same for downloads, per book.

A root view above the tabs owns the library model, the stores, and a `PlayerPresentation` (presented book plus expansion progress 0…1). An overlay interpolates the mini bar into the details screen from that progress.

**Tech Stack:** SwiftUI, Observation (`@Observable`, iOS 17), Combine (only inside the stores), AVFoundation via the existing `Player`, XCTest/XCUITest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-23-tabs-mini-player-design.md`. Read it before any task. Mockup: `.superpowers/brainstorm/81990-1792806422/content/spotify-compare.html`, the middle and right phones (in the main checkout).

## Global Constraints

- **Branch:** `feat/tabs-mini-player` in `.worktrees/tabs-mini-player`. The PR targets **`develop`**.
- **Platform:** deployment target **iOS 17.0**; never raise it. iOS 26-only APIs go behind `if #available(iOS 26, *)`.
- **Toolchain:** Xcode 26.4 (current `xcode-select`). Swift 5 mode. No third-party dependencies.
- **Test command, called `$T <onlyTesting>` below:** `xcodegen generate && xcodebuild test -project Abbay.xcodeproj -scheme Abbay -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' -derivedDataPath ./build_data -only-testing:<onlyTesting> -quiet`.
  - **UI suite:** the same with `-scheme AbbayUITests` and no `-only-testing`.
  - **Full gate:** `caffeinate -i bundle exec fastlane verify`.
  - Read counts from `xcrun xcresulttool get test-results summary --path <bundle>`.
  - Run xcodebuild in the foreground. Never poll with `pgrep -f "xcodebuild"`.
- **Colors:** only from `ColorConstants`; accent `malachite`; never `maximumRed`.
- **Strings:** new user-facing strings get a `Localizable` case, en + pt-BR in `Localizable.xcstrings`, and an entry in `LocalizationTests` (`allKeys` and `proseKeys`).
- **Accessibility:** every tappable element gets an `AccessibilityID` constant, on leaves only (`.claude/skills/verify-abbay/features/README.md`). Gestures also need VoiceOver accessibility actions.
- **Hard rule (owner):** a row that isn't playing does **zero work per clock tick**.
  - Rows never read `PlaybackClock`.
  - Never use one `ObservableObject` whose `@Published` time invalidates every observer.
  - Assign observable properties only when the value changes: Observation notifies on every set, even with an equal value.
- **Owner rules from memory:**
  - keep the `handleBackgroundEvents(completion:)` and `onAdded:` closures
  - commits use conventional subjects and carry **no Co-Authored-By trailer**
  - never push without being asked
- **Spec amendment (controller ruling):** the spec's "≤ 2 subscriptions (URL and time)" becomes **≤ 3: URL, time, and the playing status**. Today pausing produces no event; rows learn `isPlaying` from time ticks, which stop when paused. A `PlayerProtocol.isPlayingPublisher` is needed so pause shows immediately. The bound is still constant and independent of row count.

## Review Focus

1. **Pausing from the lock screen, Control Center, CarPlay or Siri:** the bar, the row and the details screen show paused within the same run-loop turn, without waiting for a tick. Test: Task 2, `test_pauseOutsideTheApp_flipsIsPlayingWithoutATick`.
2. **Deleting the loaded book while the bar is visible:** the bar and the details screen must not keep showing a deleted book, or re-insert it. Test: Task 6, `test_deletingTheLoadedBook_hidesTheBarAndClosesDetails`.
3. **Dragging the details screen down while its chapter list is scrolled:** the list scrolls; only a drag from the header, or with the list at its top, collapses. Test: Task 8, `test_collapseGesture_onlyStartsWhenListIsAtTop` (decision function).
4. **A book with no artwork, or very light artwork:** the bar's text stays readable. Test: Task 7, `test_tint_forWhiteArtwork_isDarkEnoughForWhiteText`, and `test_tint_withoutArtwork_isOnyx`.
5. **Rotating the mini player rapidly between books** (playing another book from a row while details is half-open): the overlay settles on the new book's state with no stale title or time. Test: Task 8, `test_loadedBookChangesMidDrag_overlayShowsNewBook`.

---

## File Structure

```
Abbay/Core/Playback/PlaybackState.swift        @Observable loadedBook, isPlaying            (Task 2)
Abbay/Core/Playback/PlaybackClock.swift        @Observable bookTime, currentChapter          (Task 2)
Abbay/Core/Playback/PlaybackCenter.swift       subscribes to the player once, feeds both     (Task 2)
Abbay/Core/Player/Player.swift                 + isPlayingPublisher                          (Task 2)
Abbay/LibriVox/Download/DownloadStateStore.swift  @Observable per-book entries               (Task 3)
Abbay/View/MediaView/MediaView.swift           rewritten: reads stores, one-line detail      (Task 4)
Abbay/View/MediaView/RowProgressView.swift     the only row view that reads the clock        (Task 4)
Abbay/View/Library/LibraryFilter.swift         pure local filter                             (Task 4)
Abbay/View/Search/LibriVoxSearchViewModel.swift   remote-only search (from LibrarySearchViewModel) (Task 5)
Abbay/View/Search/LibriVoxSearchView.swift     search field top, popular cards, results      (Task 5)
Abbay/View/Root/AppRootView.swift              owns stores, library model, presentation, tabs (Task 6)
Abbay/View/Root/RootTabs.swift                 iOS 26 native TabView / iOS 17–25 hand-built  (Task 6)
Abbay/View/Root/PlayerPresentation.swift       @Observable presentedBook, progress           (Task 6)
Abbay/View/MiniPlayer/MiniPlayerView.swift     one-row bar, swipes, a11y actions             (Task 7)
Abbay/View/MiniPlayer/CoverTint.swift          tint + cache                                  (Task 7)
Abbay/View/MiniPlayer/ExpansionMath.swift      pure gesture/progress/settle functions        (Task 8)
Abbay/View/MiniPlayer/PlayerExpansionOverlay.swift  interpolated bar ⇄ details               (Task 8)
Removed in Task 9: Abbay/View/FloatingPlayer/*, MediaViewModel's player code, PlayerObserver use in views
```

---

### Task 1: Spike: can iOS 26's tab bar accessory host a finger-tracked expansion?

The owner decided: native Liquid Glass tab bar on iOS 26, spike first.

**Files:**
- Create: `docs/superpowers/research/2026-10-23-tab-accessory-spike.md`
- The throwaway spike code goes on a scratch branch and is **not merged**.

**Interfaces:**
- Produces: a written verdict, `ACCESSORY_HOSTS_EXPANSION = yes | no`, that Tasks 6–8 follow.

- [ ] **Step 1:** On a scratch branch, build a minimal `TabView` with `Tab("A")`, `Tab(role: .search)` and `.tabViewBottomAccessory { bar }`. The bar gets a `DragGesture` that drives an overlay's height from 64 pt to full screen, tracking the finger.
- [ ] **Step 2:** Run it on the iPhone 17 / iOS 26.4 simulator, and record:
  - whether the gesture reaches the accessory content
  - whether the accessory can lift above the tab bar during the drag, or a sibling overlay can visually continue it
  - whether the tab bar can be hidden while expanded (`.toolbar(.hidden, for: .tabBar)`, or an equivalent)
  - whether the accessory's minimized/inline modes interfere
- [ ] **Step 3:** Write the verdict and evidence (screenshots under `.superpowers/`, not committed) in the research note.
  - **"yes":** the bar is the accessory content, and the expansion overlay starts from the accessory's frame (read via `GeometryReader` / anchor preference).
  - **"no":** the native tab bar stays, and the bar is a custom view docked above it with `safeAreaInset(edge: .bottom)` on each tab's content.
- [ ] **Step 4: Commit** the note only: `docs: Record the iOS 26 tab bar accessory spike`.

---

### Task 2: One playback source: `PlaybackCenter`, `PlaybackState`, `PlaybackClock`

**Files:**
- Create: `Abbay/Core/Playback/PlaybackState.swift`, `PlaybackClock.swift`, `PlaybackCenter.swift`
- Modify:
  - `Abbay/Core/Player/Player.swift`: add the `isPlayingPublisher`
  - `Abbay/Core/DI/DependencyContainer.swift`: add `playback: PlaybackCenter`
  - `AbbayTests/Mocks/PlayerMocks.swift`, `MockDependencyContainer.swift`
- Test: `AbbayTests/PlaybackCenterTests.swift`

**Interfaces:**
- Produces:
```swift
@Observable final class PlaybackState { private(set) var loadedBook: AudioModel?; private(set) var isPlaying = false }
@Observable final class PlaybackClock { private(set) var bookTime: Double = 0; private(set) var currentChapter: Int = 0 }
@MainActor final class PlaybackCenter {
    let state: PlaybackState; let clock: PlaybackClock
    init(player: PlayerProtocol)               // subscribes to playUrlSubjectPublisher, currentTimePublisher, isPlayingPublisher — once each
    var player: PlayerProtocol { get }         // actions go straight to the player
}
protocol PlayerProtocol { …; var isPlayingPublisher: AnyPublisher<Bool, Never> { get } }   // Player: from AVQueuePlayer.timeControlStatus (.playing or .waitingToPlayAtSpecifiedRate → true), removeDuplicates
```
- **Rules:**
  - `state.loadedBook` is set from the play-URL event. If a book is already loaded at init, seed from `player.url` and `player.currentTime` (the #116 lesson).
  - `clock.currentChapter` comes from `loadedBook.currentChapter(for: bookTime)`.
  - Each property is assigned only when its value changes.

- [ ] **Step 1: Write the failing tests** using a `CountingMockPlayer`, which counts subscriptions with `handleEvents(receiveSubscription:)` on each publisher:
  - `test_subscribesToEachPlayerPublisherExactlyOnce`: after init, URL = 1, time = 1, playing = 1. After 50 ticks, 3 URL events and 10 playing toggles, the counts are unchanged.
  - `test_alreadyLoadedBookAtInit_isSeeded`: the mock has `url` and `currentTime = 42` → `state.loadedBook?.url == url`, `clock.bookTime == 42`.
  - `test_pauseOutsideTheApp_flipsIsPlayingWithoutATick`: emit playing `true`, then `false`, with no time event → `state.isPlaying == false`.
  - `test_tick_doesNotNotifyPlaybackStateObservers`: `withObservationTracking({ _ = center.state.loadedBook; _ = center.state.isPlaying }, onChange: { fired = true })`, then emit 3 time events → `fired == false`.
  - `test_tick_notifiesClockObservers`: the same over `center.clock.bookTime` → `fired == true`.
  - `test_sameValue_doesNotRenotify`: playing `true` twice → the second emission doesn't fire tracking on `isPlaying`.
  - `test_chapterFollowsTime`: chaptered book (0/100/200) → time 150 gives `currentChapter == 1`.
- [ ] **Step 2: Run them to see them fail.** `$T AbbayTests/PlaybackCenterTests`. Expected: compile failure.
- [ ] **Step 3: Implement** the three types and `Player.isPlayingPublisher`, and register `PlaybackCenter` in `DependencyContainer`. Create it in `configure()` on main; the AppDelegate already configures on main.
- [ ] **Step 4: Run the tests to see them pass**, then `$T AbbayTests` (whole suite).
- [ ] **Step 5: Commit.** `feat: Add a single playback source with separate state and clock`

---

### Task 3: One download source, per book: `DownloadStateStore`

**Files:**
- Create: `Abbay/LibriVox/Download/DownloadStateStore.swift`
- Modify: `DependencyContainer.swift` (add `downloadStates: DownloadStateStore`), mocks
- Test: `AbbayTests/DownloadStateStoreTests.swift`

**Interfaces:**
- Consumes: `BookDownloadManagerProtocol.statesPublisher`.
- Produces:
```swift
@Observable final class BookDownloadEntry { private(set) var state: BookDownloadState? }   // nil = untracked or complete
@MainActor final class DownloadStateStore {
    init(downloads: BookDownloadManagerProtocol)   // one subscription
    func entry(for bookID: String) -> BookDownloadEntry   // stable instance per id; created on first ask
    func pause(bookID: String); func resume(bookID: String)
}
```
- **Rules:**
  - Entries live in a non-observed dictionary (`@ObservationIgnored`), so asking for an entry never makes a view depend on the whole map.
  - On each emission, update only the entries whose state changed. A complete state maps to `nil`, matching today's `downloadState` semantics.

- [ ] **Step 1: Write the failing tests:**
  - `test_subscribesToStatesPublisherOnce`: 20 emissions → 1 subscription.
  - `test_oneBookProgress_doesNotNotifyAnotherBooksEntry`: track `entry(for: "b").state`, emit a change for `"a"` only → it doesn't fire.
  - `test_completeState_mapsToNil`.
  - `test_entryIdentity_isStable`.
- [ ] **Step 2: Run them to see them fail.** `$T AbbayTests/DownloadStateStoreTests`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the tests to see them pass**, then `$T AbbayTests`.
- [ ] **Step 5: Commit.** `feat: Add a per-book download state store`

---

### Task 4: Library rows and local-only search

**Files:**
- Rewrite: `Abbay/View/MediaView/MediaView.swift`
- Create: `Abbay/View/MediaView/RowProgressView.swift`, `Abbay/View/Library/LibraryFilter.swift`
- Modify:
  - `Abbay/View/MediaView/MediaViewModel.swift`: shrink to row actions only (play, pause, toggle download), with **no** player subscriptions; delete the time and URL code
  - `MediaListView.swift`: the Library tab content
- Test: `AbbayTests/MediaViewModelTests.swift` (rewrite), `AbbayTests/LibraryFilterTests.swift`

**Interfaces:**
- Consumes: `PlaybackState`, `PlaybackClock`, `DownloadStateStore.entry(for:)`, `PlaybackCenter.player`.
- Produces:
```swift
enum LibraryFilter { static func filter(_ books: [AudioModel], query: String) -> [AudioModel] }  // title or artist; case- and diacritic-insensitive; blank → all
struct MediaView: View { init(_ book: AudioModel, namespace: String) }   // reads stores from the environment
struct RowProgressView: View { init(book: AudioModel) }                  // the ONLY row view that reads PlaybackClock; inserted only when state.loadedBook?.url == book.url
extension MediaView { struct DetailModel { init(book: AudioModel, state: PlaybackState, entry: BookDownloadEntry?); var isLoaded: Bool; var isPlaying: Bool; var detailLine: String; var downloadState: BookDownloadState? } }  // what an idle row's body reads; never touches PlaybackClock
```
- **Row layout** (spec: "one line of detail"):
  - cover (`sx64`, kept), title, then one detail line: `author · Ch N/M` when there are chapters, else `author · <time left>`.
  - The detail line comes from saved fields (`book.currentTime`) when the row isn't loaded. When it's loaded, `RowProgressView` replaces it with live values from the clock.
  - The download ring and the play button stay.
  - Existing ids are kept: `title`, `artwork`, `play`, `downloadRing`. `chapterCount` and `timestamp` become `Element.detail(namespace)`; update `AccessibilityID` and the tests.
- **Library search:** `.searchable(text:placement: .navigationBarDrawer(displayMode: .always), prompt: Localizable.librarySearchPrompt)`, filtering through `LibraryFilter`. No matches shows `Library.noResults`. The "On LibriVox" section and the remote code leave this screen; they move to Task 5.
- **New string:** `librarySearchPrompt` ("Search your library" / "Buscar na sua biblioteca").

- [ ] **Step 1: Write the failing tests:**
  - `LibraryFilterTests`: title match, artist match, `"PRIDE"` matches "Pride", `"orgulho"` matches "Orgulho e Preconceito", `"memorias"` matches "Memórias", blank returns all, no match returns empty.
  - `MediaViewModelTests` (rewritten):
    - `test_play_callsPlayerWithTheBook`
    - `test_pause_callsPlayer`
    - `test_toggleDownload_pausesThenResumes`
    - `test_rowModel_makesNoPlayerSubscriptions`: with a `CountingMockPlayer`, creating 30 row models adds 0 subscriptions.
  - `test_idleRow_readsNoClockProperty`: render-independent. Run `withObservationTracking` over `MediaView.DetailModel(book:state:entry:)` (the struct the row's body uses for its detail line), then advance the clock → it doesn't fire.
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `$T AbbayTests` **and the UI suite**. Update `AbbayUITests/AccessibilityIdentifierTests` for the renamed detail id and for the local search, which no longer shows LibriVox. Its no-results test seeds books, types `"zzzzqqq"`, and expects `library.search.noResults`.
- [ ] **Step 5: Commit.** `feat: Simplify library rows and make library search local-only`

---

### Task 5: The LibriVox Search tab

**Files:**
- Create: `Abbay/View/Search/LibriVoxSearchViewModel.swift` (moved from `LibrarySearchViewModel`, remote parts only), `Abbay/View/Search/LibriVoxSearchView.swift`
- Delete: `Abbay/View/MediaListView/LibrarySearchViewModel.swift` and its local-results code; local filtering is Task 4's
- Modify: `DebugSupport/DebugOverrides.swift` (the stub client hook moves to the new view model)
- Test: `AbbayTests/LibriVoxSearchViewModelTests.swift` (moved, minus the local cases)

**Interfaces:**
- Consumes: `LibriVoxClientProtocol`, `NetworkPathProviding`, `LibriVoxBook`.
- Produces:
```swift
@MainActor @Observable final class LibriVoxSearchViewModel {
    var query: String; private(set) var results: [LibriVoxBook]; private(set) var popular: [LibriVoxBook]
    private(set) var status: RemoteStatus          // .idle, .loading, .offline, .failed, .loaded (existing enum)
    init(client:path:debounce:)                    // same defaults as today
    func loadPopular() async
}
struct LibriVoxSearchView: View { init(onOpen: @escaping (LibriVoxBook) -> Void) }
```
- **Behavior is kept from today:** debounce, generation guard, cached popular shown offline, no request for a blank query.
- **`RemoteStatus`:** the enum moves into `LibriVoxSearchViewModel.swift`, because its old file is deleted.
- **Removed:** owned books are no longer excluded (spec: owned books appear; their details page shows Play).
- **Layout:** large title "Search", and the field at the **top** (`.searchable(placement: .navigationBarDrawer(displayMode: .always))`, prompt `librivoxSearchPrompt`). With an empty query: a section header `popularOnLibriVox` above a 2-column `LazyVGrid` of cards. A card is the cover (`AsyncImage`, `onyx` placeholder) at 1:1, with the title (2 lines) below.
- **Results:** the existing `RemoteBookRow`, moved here. A card or row tap calls `onOpen(book)`.
- **Ids:** `Search.card(index)`, `Search.result(index)`, `Search.message`, `Search.noResults`.
- **New string:** `librivoxSearchPrompt` ("Search LibriVox" / "Buscar no LibriVox").

- [ ] **Step 1: Write the failing tests:** carry over every remote test from `LibrarySearchViewModelTests` (debounce, offline, cached popular offline, failure, stale-generation guard, clear restores popular). Add `test_ownedBooks_areNotExcluded`, and remove the local-filter tests.
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement.** Add a UI test `test_searchTab_showsPopularCards_andOpensDetails`: stub client, open the Search tab, `Search.card(0)` exists, tap it, `detail.view` exists. The tab is wired in Task 6, so this UI test is written here but enabled in Task 6.
- [ ] **Step 4: Run the tests to see them pass.**
- [ ] **Step 5: Commit.** `feat: Add the LibriVox search view with popular cards`

---

### Task 6: Root, tabs and one place that presents the player

**Files:**
- Create: `Abbay/View/Root/AppRootView.swift`, `Abbay/View/Root/RootTabs.swift`, `Abbay/View/Root/PlayerPresentation.swift`
- Modify:
  - `Abbay/AbbayApp.swift`: `WindowGroup { AppRootView() }`
  - `MediaListView.swift`: becomes the Library tab content; loses its own `NavigationStack` sheets for the player, `openedBook` and the search state
  - `MediaListViewModel.swift`:
    - drop the `PlayerObserver`; `selectedAudio` comes from `PlaybackState`
    - `deleteAudio` closes the details screen if it shows the deleted book
    - when the deleted book is the loaded one, ask the player to unload (`player.cleanup()` + clear), so the bar disappears
  - `LibriVoxDetailView.swift`/`ViewModel`: remove the `.sheet { PlayerView }`; `play()` calls an injected `openPlayer: (AudioModel) -> Void`
  - `AccessibilityID`, `Localizable`
- Test: `AbbayTests/PlayerPresentationTests.swift`, `AbbayTests/MediaListViewModelTests.swift`, UI tests

**Interfaces:**
- Consumes: Task 1's verdict, Tasks 2–5.
- Produces:
```swift
enum RootTab: Hashable { case library, search }
@MainActor @Observable final class PlayerPresentation {
    private(set) var presentedBook: AudioModel?      // what the details screen shows
    var progress: CGFloat = 0                         // 0 = collapsed into the bar, 1 = fully open
    func open(_ book: AudioModel, animated: Bool)     // sets presentedBook, animates progress → 1
    func close(animated: Bool)                        // animates progress → 0, then clears presentedBook
}
struct AppRootView: View   // owns MediaListViewModel, PlayerPresentation, selected RootTab; injects PlaybackCenter, DownloadStateStore, PlayerPresentation via .environment
```
- **Tabs:**
  - **iOS 26:** `TabView(selection:)` with `Tab(Localizable.libraryTab, systemImage: "books.vertical", value: .library)` and `Tab(Localizable.searchTab, systemImage: "magnifyingglass", value: .search, role: .search)`. The accessory or the custom bar follows Task 1's verdict.
  - **iOS 17–25:** `RootTabs` draws an equivalent bar: `background2` fill, the two items, malachite when selected.
  - Each tab has its own `NavigationStack`.
  - The Library toolbar keeps ＋ (now only `Import file`, id `Library.menuImport`) and ⚙️. The empty Library's primary button sets the tab to `.search`.
- **Ids:** `Root.tabLibrary`, `Root.tabSearch`.
- **New strings:** `libraryTab` ("Library" / "Biblioteca"), `searchTab` ("Search" / "Buscar").
- **One presentation:** a row tap, the mini bar tap, and the details page's Play all call `presentation.open`. Nothing presents `PlayerView` as a sheet any more.

- [ ] **Step 1: Write the failing tests:**
  - `test_open_setsBookAndTargetsFullProgress`
  - `test_close_clearsBookAfterCollapse`
  - `test_deletingTheLoadedBook_hidesTheBarAndClosesDetails`: `MediaListViewModel` with a mock player whose `url` equals the book's → after `deleteAudio`, the player got `cleanup`, the presentation was closed, and the store's `loadedBook` is nil once the player publishes.
  - UI tests:
    - `test_tabs_switchBetweenLibraryAndSearch`: the `Root.tabLibrary` and `Root.tabSearch` ids exist, and tapping Search shows the field with the `librivoxSearchPrompt` placeholder.
    - Enable Task 5's `test_searchTab_showsPopularCards_andOpensDetails`.
    - `test_emptyLibrary_browseButton_opensSearchTab`.
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `$T AbbayTests` **and the UI suite**.
- [ ] **Step 5: Commit.** `feat: Add Library and Search tabs with a single player presentation`

---

### Task 7: The one-row mini player

**Files:**
- Create: `Abbay/View/MiniPlayer/MiniPlayerView.swift`, `Abbay/View/MiniPlayer/CoverTint.swift`
- Modify: `RootTabs.swift` (place the bar as Task 1 decided), `AccessibilityID`, `Localizable`
- Test: `AbbayTests/CoverTintTests.swift`, `AbbayTests/MiniPlayerActionsTests.swift`

**Interfaces:**
- Consumes: `PlaybackState`, `PlaybackClock`, `PlaybackCenter.player`, `PlayerPresentation`.
- Produces:
```swift
enum CoverTint {
    static func color(for imageData: Data?) -> UIColor   // nil/undecodable → ColorConstants.onyx; else average of a ≤16×16 downscale, darkened (HSB brightness ×0.9 steps) until contrast vs white ≥ 4.5
    static func cached(for book: AudioModel) -> UIColor   // NSCache keyed by book.url
}
enum MiniPlayerActions {
    static func nextChapter(player: PlayerProtocol, book: AudioModel, chapter: Int) -> Bool   // false (→ haptic) on last chapter or no chapters
    static func restartChapter(player: PlayerProtocol, book: AudioModel, chapter: Int) -> Bool // seek(chapters[chapter].startTime); false if no chapters
}
struct MiniPlayerView: View   // height 56 pt; cover 40 pt (radius sx4); title (semibold 13) + subtitle "Chapter N · X min left" (localized `miniPlayerSubtitle` %d/%@); play/pause; 2 pt progress line at the bottom edge (chapter progress, white on 25% white)
```
- **Body split:** the bar's outer body reads only `PlaybackState`. The subtitle and the progress line are a child view that reads `PlaybackClock`.
- **Gestures:**
  - **Tap:** `presentation.open(loadedBook, animated: true)`.
  - **Horizontal swipe:** past 40 pt, with the horizontal component greater than the vertical, `nextChapter` (left) or `restartChapter` (right). A `false` result gives `UIImpactFeedbackGenerator(style: .light)`. The text slides 12 pt in the swipe's direction and back.
  - **Vertical drag:** handed to Task 8.
- **Accessibility:** the element combines title and subtitle, with `.accessibilityAction(named: Localizable.openPlayer)` → open, plus `nextChapter` and `restartChapter` actions.
- **Ids:** `MiniPlayer.bar` (leaf: on the title/subtitle text group, **not** the container; this fixes the earlier container-id finding), `MiniPlayer.playPause`, `MiniPlayer.progress`.
- **New strings:**
  - `miniPlayerSubtitle`: "Chapter %d · %@ left" / "Capítulo %d · faltam %@"
  - `openPlayer`: "Open player" / "Abrir player"
  - `nextChapterAction`: "Next chapter" / "Próximo capítulo"
  - `restartChapterAction`: "Restart chapter" / "Reiniciar capítulo"
- **Visibility:** shown when `state.loadedBook != nil` and `presentation.progress < 1`.
- **Insets (spec anti-goal):** each tab's scroll content gets a bottom inset of the bar's height plus the tab bar's, via `safeAreaInset(edge: .bottom)` or the accessory's own inset on iOS 26, so the bar never covers the last row. UI test `test_lastRow_isNotCoveredByMiniPlayer`: seed the library, play the stub book, scroll to the bottom → the last row's `title` frame's `maxY` ≤ `MiniPlayer.bar`'s `minY`.

- [ ] **Step 1: Write the failing tests:**
  - `test_tint_withoutArtwork_isOnyx`
  - `test_tint_forWhiteArtwork_isDarkEnoughForWhiteText`: a 4×4 white PNG gives a contrast ratio ≥ 4.5
  - `test_tint_forDarkArtwork_isUnchangedRoughly`
  - `test_tint_isCachedPerBook`
  - `test_nextChapter_onLastChapter_returnsFalseAndDoesNotCallPlayer`
  - `test_nextChapter_callsSkipToNextChapter`
  - `test_restartChapter_seeksToChapterStart` (chapter 1 starting at 100 → `seek(100)`)
  - `test_noChapters_bothReturnFalse`
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement** the bar and place it.
- [ ] **Step 4: Run the tests, then the UI suite.** Update the old floating-player UI test, `test_search_showsFloatingPlayerAfterPlayingFromDetail`, to assert `MiniPlayer.bar` after playing the stub book. Add `test_tappingMiniPlayer_opensDetails`.
- [ ] **Step 5: Commit.** `feat: Add the one-row mini player docked above the tabs`

---

### Task 8: Interactive expansion into the details screen

**Files:**
- Create: `Abbay/View/MiniPlayer/ExpansionMath.swift`, `Abbay/View/MiniPlayer/PlayerExpansionOverlay.swift`
- Modify:
  - `Abbay/View/PlayerView/PlayerView.swift` and `PlayerViewModel.swift`:
    - reads `PlaybackState` and `PlaybackClock` when `presentedBook` is the loaded book, else the book's saved fields
    - **no** `PlayerObserver`, and no download sink: uses `DownloadStateStore.entry`
  - `AppRootView.swift`
- Test: `AbbayTests/ExpansionMathTests.swift`, `AbbayTests/PlayerViewModelTests.swift` (rewrite)

**Interfaces:**
- Consumes: `PlayerPresentation`, the bar frame from Task 7 (via anchor preference), the stores.
- Produces:
```swift
enum ExpansionMath {
    static let openThreshold: CGFloat = 0.30, flickVelocity: CGFloat = 800      // spec values
    static func progress(start: CGFloat, translationY: CGFloat, travel: CGFloat) -> CGFloat   // clamp 0…1; drag up (negative y) increases
    static func shouldOpen(progress: CGFloat, velocityY: CGFloat, wasOpening: Bool) -> Bool   // opening: progress ≥ 0.30 or velocity ≤ -800; closing: mirrored (progress > 0.70 and velocity < 800 → stay open)
    static func canStartCollapse(listOffset: CGFloat, fromHeader: Bool) -> Bool                // fromHeader || listOffset <= 0
    static func interpolate(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect
}
```
- **Overlay:** draws a single container whose frame interpolates from the bar's frame to the full screen with `progress`.
  - Corner radius goes from 8 to 0. The cover goes from 40 pt to the details cover size, using `matchedGeometryEffect` or interpolation.
  - The bar's content fades out over the first 30% while `PlayerView`'s content fades in over the last 70%.
  - The tab bar's offset follows the progress (hidden at 1).
  - A `DragGesture` on the bar (vertical) and on the details header or grabber updates `progress` live, with no animation while dragging. On end, `withAnimation(.spring(response: 0.35, dampingFraction: 0.86))` goes to 1 or 0 per `shouldOpen`.
  - **Interruptible:** grabbing mid-spring continues from the current `progress`.
  - **Reduce Motion:** `@Environment(\.accessibilityReduceMotion)` gives an opacity cross-fade between the same end states, with no frame interpolation.
  - Row taps and the LibriVox page's Play call `open(_, animated: true)`. The same overlay animates from the bar's frame, or from a 56 pt strip at the bottom edge when no bar is visible.
- **The details screen keeps its look:** cover, transport, `ChapterListView`. It drops its sheet grabber and gains a top grabber that's the collapse handle.

- [ ] **Step 1: Write the failing tests** (`ExpansionMathTests`):
  - `progress(start:0, translationY:-150, travel:600) == 0.25`
  - clamps below 0 and above 1
  - `shouldOpen(0.31, 0, true) == true`; `shouldOpen(0.10, -900, true) == true`; `shouldOpen(0.29, -100, true) == false`
  - mirrored closing cases: `shouldOpen(0.69, 0, false) == false`; `shouldOpen(0.95, 900, false) == false`
  - `test_collapseGesture_onlyStartsWhenListIsAtTop`: `canStartCollapse(listOffset: 120, fromHeader: false) == false`, `(0, false) == true`, `(120, true) == true`
  - `interpolate` midpoint

  And in `PlayerViewModelTests`:
  - `test_presentedLoadedBook_readsPlaybackStores`
  - `test_presentedOtherBook_showsSavedPosition_andPlayLoadsIt`
  - `test_loadedBookChangesMidDrag_overlayShowsNewBook`: the presentation shows the loaded book, then the state's `loadedBook` changes → the view model's displayed book is the new one, and `bookTime` comes from the clock.
  - `test_playerViewModel_makesNoPlayerSubscriptions` (counting mock: 0).
- [ ] **Step 2: Run them to see them fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `$T AbbayTests` **and the UI suite.** Add UI tests:
  - `test_draggingMiniPlayerUp_opensDetails`: `press(forDuration:0.1, thenDragTo:)` from `MiniPlayer.bar` to the top of the screen → `player.transport.play` exists.
  - `test_draggingDetailsDown_collapses`: drag from the grabber to the bottom → `MiniPlayer.bar` exists and the transport doesn't.
- [ ] **Step 5: Commit.** `feat: Expand the mini player into the details screen under the finger`

---

### Task 9: Remove the old player plumbing and prove the subscription budget

**Files:**
- Delete: `Abbay/View/FloatingPlayer/FloatingPlayerView.swift`, `FloatingPlayerViewModel.swift`, `AbbayTests/FloatingPlayerViewModelTests.swift`
- Modify: remove every `PlayerObserver(...)` default and `subscribeTo…` call outside `CarPlaySceneDelegate`. `PlayerObserver` stays for CarPlay; add a comment there naming it the one remaining consumer.
- Modify: `.claude/skills/verify-abbay/features/`:
  - new `tabs.md` and `mini-player.md`
  - update `library.md`, `floating-player.md` (→ redirect to `mini-player.md`, or delete and fix links), `player.md`, `media-row.md`, `librivox-details.md`, `README.md`
- Test: `AbbayTests/SubscriptionBudgetTests.swift`

- [ ] **Step 1: Write the failing test.** `test_appWide_playerSubscriptions_stayAtThree`:
  - Build the real `PlaybackCenter` + `DownloadStateStore` with counting mocks, plus 25 `MediaViewModel`s, a `PlayerViewModel`, and the mini player's model. Open and close the presentation 3 times, and emit 30 ticks.
  - Assert player subscriptions == 3 and `statesPublisher` subscriptions == 1.
  - It fails if any leftover view model still subscribes.
- [ ] **Step 2: Run it to see it fail** (or pass, if Tasks 4–8 already removed everything; then confirm by temporarily adding a `PlayerObserver` to a row model, see it fail, and revert).
- [ ] **Step 3: Delete the dead code and update the feature map.** The map must list every new id, mark which are verified by UI tests, and record Task 1's verdict.
- [ ] **Step 4: Run** the full gate: `caffeinate -i bundle exec fastlane verify` → lint clean, unit and UI suites pass. Report counts.
- [ ] **Step 5: Commit.** `refactor: Remove the per-view player observers and the old floating player`
