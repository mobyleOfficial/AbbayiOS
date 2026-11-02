//
//  AppRootView.swift
//  Abbay
//

import Combine
import SwiftUI

/// The app's root: the Library and Search tabs, each with its own `NavigationStack`, and above
/// them the one overlay that presents the details screen, growing out of the mini player. It owns the library model, the player
/// presentation and the selected tab, and injects the app-wide playback and download sources.
/// Over everything sits the error banner (`NoticeBannerView`), the only reader of `NoticeCenter`.
///
/// The body reads only the selected tab. Playback and presentation state are read by small leaf
/// views (`LoadedBookObserver`, `PlayerExpansionOverlay`, the mini player's `MiniPlayerDock` /
/// `MiniPlayerAccessory`, the tab bars' `TabBarHiddenWhilePlayerIsOpen` /
/// `HiddenWhilePlayerIsOpen`), so a tick, a book switch or a drag never rebuilds the tab view.
/// The library model is held, not observed: only `MediaListView` observes it, so an import or a
/// delete re-renders the Library list, not the root.
///
/// Adaptive (#255): `AdaptiveLayoutReader` decides from the room the app is given whether the
/// window is split (`PaneLayout`). Split, each tab hosts the player and chapter panes beside
/// browsing (`BrowsingPanes`) and the overlay draws nothing; in one pane, the overlay presents the
/// player as before. Both read the same `PlayerPresentation`, so a fold keeps what is open.
struct AppRootView: View {
    private let container: DependencyContainerProtocol
    private let notices: NoticeCenter
    @StateObject
    private var models: RootModels
    @State
    private var selectedTab: RootTab = .library
    @State
    private var isShowingSettings = false

    private var model: MediaListViewModel { models.library }
    private var presentation: PlayerPresentation { models.presentation }

    /// Builds from `DependencyContainer.shared`, so it must run after `didFinishLaunching`
    /// configured the container (it does: the scene's body is evaluated after launch).
    init(container: DependencyContainerProtocol = DependencyContainer.shared, notices: NoticeCenter = .shared) {
        self.container = container
        self.notices = notices
        _models = StateObject(wrappedValue: RootModels(playback: container.playback))
    }

    var body: some View {
        AdaptiveLayoutReader(presentation: presentation) {
            ZStack {
                tabs
                PlayerExpansionOverlay(models: models.details)
                // The read-along text full screen (#192): over the player and browsing alike.
                ReadAlongFullScreenHost()
            }
        }
        // Strings are read when a body runs, so a language switch rebuilds the tabs and the player
        // (their models live above, in `models`, and survive). The Settings sheet is presented
        // outside this subtree, so it stays open and redraws itself.
        .id(container.settings.language)
        // Above the details screen too, and at the top, clear of the mini player and the tab bar.
        .overlay(alignment: .top) {
            NoticeBannerView()
        }
        .environment(notices)
        .environment(\.locale, AbbayBundle.locale)
        .background {
            LoadedBookObserver(model: model)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(model: SettingsViewModel(settings: container.settings, library: settingsLibrary))
        }
        .environment(presentation)
        .environment(container.settings)
        .playbackEnvironment(container)
        .preferredColorScheme(.dark)
    }

    /// Settings deletes finished books through the library model, the same path as a swipe.
    private var settingsLibrary: SettingsLibrary {
        SettingsLibrary(
            books: container.loadAllAudios.execute,
            downloadState: { [downloads = container.downloadStates] in downloads.entry(for: $0).state },
            delete: { [model] books in model.deleteAudios(books) }
        )
    }

    // MARK: - Tabs

    /// The system tab bar from 26.1, which also has `.tabViewBottomAccessory(isEnabled:)` for the
    /// docked bar; the hand-built one before. Two code paths, as the owner accepted.
    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 26.1, *) {
            SystemTabs(selection: tabSelection, library: libraryTab, search: searchTab)
        } else {
            RootTabs(selection: tabSelection) {
                libraryTab
            } search: {
                searchTab
            } accessory: {
                MiniPlayerDock()
            }
        }
    }

    private var libraryTab: some View {
        NavigationStack {
            MediaListView(model: model, onBrowse: { selectTab(.search) }, onSettings: { isShowingSettings = true })
                .modifier(TabBarHiddenWhilePlayerIsOpen())
                .modifier(HiddenNavigationBarWhileCovered())
        }
        .modifier(BrowsingPanes(isSelected: selectedTab == .library, models: models.details))
    }

    private var searchTab: some View {
        SearchTab(library: model, onAdded: { [model] in model.addLibriVoxBook($0) })
            .modifier(BrowsingPanes(isSelected: selectedTab == .search, models: models.details))
    }

    /// Switching tabs while the chapters stand in browsing's place brings browsing back (on the
    /// chosen tab) beside the player. In one pane the chapters float over the player, which
    /// covers the tabs, so a switch can't come from there.
    private var tabSelection: Binding<RootTab> {
        Binding(get: { selectedTab }, set: { selectTab($0) })
    }

    private func selectTab(_ tab: RootTab) {
        if presentation.usesPanes { presentation.setChapters(open: false) }
        if selectedTab != tab { selectedTab = tab }
    }
}

// MARK: - Models

/// The root's long-lived models, created once. An `ObservableObject` with nothing `@Published`, so
/// it never invalidates the root: `@StateObject` here only keeps them alive (unlike `@State`, it
/// doesn't rebuild a throwaway library model, which loads from storage, on every init).
@MainActor
private final class RootModels: ObservableObject {
    let presentation: PlayerPresentation
    let library: MediaListViewModel
    /// The player's model per presentation, shared by the full-screen player and the player pane.
    let details = PlayerDetailsModels()

    private var chapterChanges: AnyCancellable?
    private var titleChanges: AnyCancellable?

    init(playback: PlaybackCenter) {
        let presentation = PlayerPresentation(playback: playback.state)
        self.presentation = presentation
        let library = MediaListViewModel(playback: playback, presentation: presentation)
        self.library = library
        let details = details
        // Chapters found in a book's audio, or removed (`ChapterFinder`): its row and the player
        // showing it take them. The loaded book's copy is the playback center's own.
        chapterChanges = NotificationCenter.default.publisher(for: .bookChaptersDidChange)
            .sink { notification in
                guard let url = notification.object as? URL,
                      let chapters = notification.userInfo?[ChapterFinder.chaptersKey] as? [ChapterModel]
                else { return }
                MainActor.assumeIsolated {
                    library.chaptersChanged(ofBookAt: url)
                    presentation.chaptersChanged(chapters, ofBookAt: url)
                    details.chaptersChanged(chapters, ofBookAt: url)
                }
            }
        // A book renamed (#322): the same holders take its new title.
        titleChanges = NotificationCenter.default.publisher(for: .bookTitleDidChange)
            .sink { notification in
                guard let url = notification.object as? URL,
                      let title = notification.userInfo?[BookRenamer.titleKey] as? String
                else { return }
                MainActor.assumeIsolated {
                    library.chaptersChanged(ofBookAt: url)
                    presentation.titleChanged(title, ofBookAt: url)
                    details.titleChanged(title, ofBookAt: url)
                }
            }
    }
}

// MARK: - System tabs

@available(iOS 26.1, *)
private struct SystemTabs<Library: View, Search: View>: View {
    @Binding
    var selection: RootTab
    let library: Library
    let search: Search

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: RootTab.library) {
                library
            } label: {
                Label(Localizable.libraryTab.localized, systemImage: "books.vertical")
            }
            // Reaches the system bar's button when built with the iOS 27 SDK, but not every time
            // (#154), so `TabBarIdentifiers` still sets the ids as well.
            .accessibilityIdentifier(AccessibilityID.Root.tabLibrary)
            // A regular tab, not `role: .search`: that role moves the tab's search field into the
            // bottom tab bar, and the owner wants it at the top, like the Library's.
            Tab(value: RootTab.search) {
                search
            } label: {
                Label(Localizable.searchTab.localized, systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier(AccessibilityID.Root.tabSearch)
        }
        .tint(ColorConstants.malachite.value)
        .modifier(MiniPlayerAccessory())
        .background {
            TabBarIdentifiers(
                identifiers: [AccessibilityID.Root.tabLibrary, AccessibilityID.Root.tabSearch],
                selection: selection
            )
        }
    }
}

/// SwiftUI's `TabContent.accessibilityIdentifier` doesn't reliably reach the system tab bar's
/// buttons, so this sets the ids too. It finds the window's `UITabBar` and sets them on its items,
/// in tab order, and on any other view in the bar labelled with an item's title (the bar can show
/// a tab as a separate, collapsed button). Only identifiers; nothing else is touched. Re-applied on
/// each tab switch, while the bar animates.
///
/// Why it stays (#130, #154): built with the iOS 26.4 SDK, the SwiftUI identifier never reached the
/// button. Built with the iOS 27 SDK (Xcode 27.1) it usually does, on the 26.4 and 27.1 runtimes,
/// but with this probe removed `root.tab.search` was still missing in a few UI tests per suite run
/// on both. Retry on the next SDK.
@available(iOS 26.1, *)
private struct TabBarIdentifiers: UIViewRepresentable {
    let identifiers: [String]
    /// Not read: passing it makes SwiftUI call `updateUIView` on each tab switch.
    let selection: RootTab

    func makeUIView(context: Context) -> ProbeView {
        ProbeView(identifiers: identifiers)
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.scheduleApply()
    }

    final class ProbeView: UIView {
        let identifiers: [String]
        /// After a trigger, the bar is installed or rebuilt at a time UIKit doesn't announce: apply
        /// on each of these delays (seconds), which cover a slow switch animation. Applying is
        /// idempotent and cheap (assigned only where missing).
        static let applyDelays: [TimeInterval] = [0, 0.1, 0.3, 0.6, 1.2, 2.4]
        /// Bumped by each trigger, so a burst of switches runs one schedule, the latest.
        private var schedule = 0

        init(identifiers: [String]) {
            self.identifiers = identifiers
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleApply()
        }

        /// The bar is installed, and rebuilt on a switch, after this runs: apply as it settles.
        func scheduleApply() {
            schedule += 1
            let current = schedule
            for delay in Self.applyDelays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, schedule == current else { return }
                    apply()
                }
            }
        }

        private func apply() {
            guard let window, let tabBar = Self.tabBar(in: window) else { return }
            for (item, identifier) in zip(tabBar.items ?? [], identifiers) {
                if item.accessibilityIdentifier != identifier { item.accessibilityIdentifier = identifier }
                guard let title = item.title else { continue }
                for view in Self.views(in: tabBar) where view.accessibilityLabel == title
                    && view.accessibilityIdentifier == nil {
                    view.accessibilityIdentifier = identifier
                }
            }
        }

        private static func tabBar(in view: UIView) -> UITabBar? {
            if let tabBar = view as? UITabBar { return tabBar }
            for subview in view.subviews {
                if let found = tabBar(in: subview) { return found }
            }
            return nil
        }

        private static func views(in view: UIView) -> [UIView] {
            view.subviews + view.subviews.flatMap(views(in:))
        }
    }
}

// MARK: - Search tab

/// LibriVox search, pushing the details page for a card or a result. The pushed book is state
/// here, not row-owned, so adding the book can't pop the page.
private struct SearchTab: View {
    /// Observed here, not at the root, so only this tab re-renders when the library changes: the
    /// result rows say Open for a book that is already in it.
    @ObservedObject
    var library: MediaListViewModel
    let onAdded: (AudioModel) -> Void

    @Environment(PlayerPresentation.self)
    private var presentation
    @State
    private var openedBook: LibriVoxBook?

    var body: some View {
        NavigationStack {
            LibriVoxSearchView(libraryBookIDs: libraryBookIDs, onOpen: { openedBook = $0 })
                .modifier(TabBarHiddenWhilePlayerIsOpen())
                .modifier(HiddenNavigationBarWhileCovered())
                .navigationDestination(item: $openedBook) { book in
                    LibriVoxDetailView(
                        book: book,
                        onAdded: onAdded,
                        openPlayer: { [presentation] in presentation.open($0, animated: true) }
                    )
                    .modifier(TabBarHiddenWhilePlayerIsOpen())
                    .modifier(HiddenNavigationBarWhileCovered())
                }
        }
    }

    private var libraryBookIDs: Set<String> {
        Set(library.audioList.compactMap { LibriVoxIdentity.bookID(from: $0.url) })
    }
}

// MARK: - Layout

/// Measures the room the app's content is given and decides the split (`AdaptiveLayout`), for the
/// environment below and for the presentation. Re-decides on a fold, a rotation, a window resize or
/// a text size change; only the decision, not the size, reaches the content, so a resize that
/// keeps the split re-renders nothing below.
private struct AdaptiveLayoutReader<Content: View>: View {
    let presentation: PlayerPresentation
    @ViewBuilder let content: Content

    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize
    @State
    private var size: CGSize = .zero

    var body: some View {
        let layout = AdaptiveLayout.decide(
            width: size.width,
            height: size.height,
            horizontalSizeClass: horizontalSizeClass,
            dynamicTypeSize: dynamicTypeSize
        )
        content
            .environment(\.paneLayout, layout)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.size, initial: true) { _, new in size = new }
                }
            }
            .onChange(of: layout.isSplit, initial: true) { _, split in
                presentation.layoutChanged(usesPanes: split)
            }
    }
}

// MARK: - Loaded book

/// Hands each book switch to the library model, which re-reads the outgoing and incoming books
/// from storage. Reads only `PlaybackState.loadedBook`, so it runs once per switch, never per tick.
private struct LoadedBookObserver: View {
    let model: MediaListViewModel

    @Environment(PlaybackState.self)
    private var playback

    var body: some View {
        Color.clear
            .onChange(of: playback.loadedBook?.url) {
                model.loadedBookChanged(to: playback.loadedBook)
            }
    }
}
