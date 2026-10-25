//
//  AppRootView.swift
//  Abbay
//

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
        ZStack {
            tabs
            PlayerExpansionOverlay()
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
            SystemTabs(selection: $selectedTab, library: libraryTab, search: searchTab)
        } else {
            RootTabs(selection: $selectedTab) {
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
            MediaListView(model: model, onBrowse: { selectedTab = .search }, onSettings: { isShowingSettings = true })
                .modifier(TabBarHiddenWhilePlayerIsOpen())
        }
    }

    private var searchTab: some View {
        SearchTab(onAdded: { [model] in model.addLibriVoxBook($0) })
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

    init(playback: PlaybackCenter) {
        let presentation = PlayerPresentation(playback: playback.state)
        self.presentation = presentation
        library = MediaListViewModel(playback: playback, presentation: presentation)
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
            // On the system bar's button since the iOS 27 SDK (#154): built with the iOS 26.4 SDK it
            // didn't reach the button, and a UIKit probe set the ids instead.
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
    }
}

// MARK: - Search tab

/// LibriVox search, pushing the details page for a card or a result. The pushed book is state
/// here, not row-owned, so adding the book can't pop the page.
private struct SearchTab: View {
    let onAdded: (AudioModel) -> Void

    @Environment(PlayerPresentation.self)
    private var presentation
    @State
    private var openedBook: LibriVoxBook?

    var body: some View {
        NavigationStack {
            LibriVoxSearchView(onOpen: { openedBook = $0 })
                .modifier(TabBarHiddenWhilePlayerIsOpen())
                .navigationDestination(item: $openedBook) { book in
                    LibriVoxDetailView(
                        book: book,
                        onAdded: onAdded,
                        openPlayer: { [presentation] in presentation.open($0, animated: true) }
                    )
                    .modifier(TabBarHiddenWhilePlayerIsOpen())
                }
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
