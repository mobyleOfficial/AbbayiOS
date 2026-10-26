//
//  ContentView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 14/06/23.
//

import SwiftUI

/// The Library tab ("Library B", #166 G3): the Continue card for the last played book, then every
/// book in a three-column cover grid, a local-only search over them, the empty state and the
/// toolbar. The root owns the model and the tab's `NavigationStack`; LibriVox lives in the Search
/// tab.
///
/// Nothing here paints a background: the system's own lets the scroll edge effect work under the
/// navigation bar and the tab bar.
struct MediaListView: View {
    // MARK: - Properties
    @ObservedObject
    var model: MediaListViewModel
    /// Switches to the Search tab (the empty state's primary button).
    let onBrowse: () -> Void
    /// Opens the Settings sheet, which the root presents.
    var onSettings: VoidCallback?

    @Environment(PlayerPresentation.self)
    private var presentation
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize
    @State
    private var query = ""
    /// Where the Continue card finds the last played book.
    var lastPlayed: LastPlayedStore = .shared

    // MARK: - Body
    var body: some View {
        contentView
            .navigationTitle(Localizable.libraryTitle.localized)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    addMenu
                    Button {
                        onSettings?()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Localizable.settingsTitle.localized)
                    .accessibilityIdentifier(AccessibilityID.Library.toolbarSettings)
                }
            }
            .sheet(isPresented: $model.isShowingFilePicker) {
                DocumentPickerView(onImport: { urls in
                    await model.importAudio(from: urls)
                })
            }
            .foregroundColor(ColorConstants.white.value)
    }

    // MARK: - Toolbar
    /// Only Import file: the Search tab replaced "Browse LibriVox".
    var addMenu: some View {
        Menu {
            Button {
                model.startImport()
            } label: {
                Label(Localizable.importFile.localized, systemImage: "folder.badge.plus")
            }
            .accessibilityIdentifier(AccessibilityID.Library.menuImport)
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel(Localizable.addMenu.localized)
        .accessibilityIdentifier(AccessibilityID.Library.toolbarAdd)
    }

    // MARK: - Content View
    @ViewBuilder
    var contentView: some View {
        if model.audioList.isEmpty {
            emptyView
        } else {
            libraryView
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Localizable.librarySearchPrompt.localized
            )
        }
    }

    // MARK: - Empty View
    var emptyView: some View {
        ContentUnavailableView {
            Label {
                Text(Localizable.emptyLibraryTitle.localized)
                    .accessibilityIdentifier(AccessibilityID.Library.empty)
            } icon: {
                Image(systemName: "books.vertical")
                    .accessibilityHidden(true)
            }
        } description: {
            Text(Localizable.emptyLibraryMessage.localized)
        } actions: {
            Button {
                onBrowse()
            } label: {
                Text(Localizable.browseFreeAudiobooks.localized)
                    .font(.headline)
                    .foregroundStyle(ColorConstants.background2.value)
                    .padding(.horizontal, SpaceConstants.sx8.value)
            }
            .abbayGlassProminentButton()
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .accessibilityIdentifier(AccessibilityID.Library.emptyBrowse)
            Button {
                model.startImport()
            } label: {
                Text(Localizable.importAFile.localized)
                    .font(.headline)
                    .padding(.horizontal, SpaceConstants.sx8.value)
            }
            .abbayGlassButton()
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(ColorConstants.white.value)
            .accessibilityIdentifier(AccessibilityID.Library.emptyImport)
        }
    }

    // MARK: - Library View
    private var isSearching: Bool {
        !trimmedQuery.isEmpty
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Three columns up to the default text size; two from *xLarge* up, so a two-line title still
    /// fits at the largest non-accessibility size (*xxxLarge* truncated in three columns).
    private var columns: [GridItem] {
        let count = dynamicTypeSize >= .xLarge ? 2 : 3
        return Array(
            repeating: GridItem(.flexible(), spacing: SpaceConstants.sx12.value, alignment: .top),
            count: count
        )
    }

    @ViewBuilder
    var libraryView: some View {
        let books = LibraryFilter.filter(model.audioList, query: query)
        if books.isEmpty {
            // The system's search empty state, built from our strings so it follows the in-app
            // language (`ContentUnavailableView.search` reads the device's).
            ContentUnavailableView {
                Label {
                    Text(Localizable.noResultsFor.localized(with: trimmedQuery))
                        .accessibilityIdentifier(AccessibilityID.Library.noResults)
                } icon: {
                    Image(systemName: "magnifyingglass")
                        .accessibilityHidden(true)
                }
            } description: {
                Text(Localizable.noResultsHint.localized)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: SpaceConstants.sx8.value) {
                    if !isSearching {
                        ContinueSection(books: model.audioList, lastPlayed: lastPlayed) { book in
                            presentation.open(book, animated: true)
                        }
                        LibrarySectionHeader(title: .libraryAllBooks)
                    }
                    grid(books)
                }
                .padding(.horizontal, SpaceConstants.sx16.value)
                .padding(.bottom, SpaceConstants.sx16.value)
            }
            .accessibilityIdentifier(AccessibilityID.Library.list)
        }
    }

    private func grid(_ books: [AudioModel]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: SpaceConstants.sx16.value) {
            // `enumerated()` keeps url-based identity while exposing the positional index the
            // accessibility identifiers use.
            ForEach(Array(books.enumerated()), id: \.element.url) { index, file in
                MediaView(
                    file,
                    namespace: AccessibilityID.Library.row(index),
                    // As before: while searching, a fully downloaded LibriVox book says so.
                    showsDownloadedBadge: isSearching,
                    onOpen: { presentation.open(file, animated: true) },
                    onDelete: { model.deleteAudio(file) }
                )
            }
        }
    }
}

// MARK: - Subviews
/// A section's title: "Continue", "All books".
private struct LibrarySectionHeader: View {
    let title: Localizable

    var body: some View {
        Text(title.localized)
            .font(.title3.weight(.bold))
            .accessibilityAddTraits(.isHeader)
            .padding(.top, SpaceConstants.sx8.value)
    }
}

/// "Continue" and its card, or nothing when there is no book to continue (`ContinueCard.book`).
/// Its own view, so the play / pause and book switches it follows (through `PlaybackState`)
/// re-run only it, not the grid.
private struct ContinueSection: View {
    let books: [AudioModel]
    let lastPlayed: LastPlayedStore
    let onOpen: (AudioModel) -> Void

    @Environment(PlaybackState.self)
    private var playback

    /// Reads `PlaybackState` first, so a play (which saves last played before it reports
    /// playing) or a book switch re-runs the body, which re-reads last played.
    private var lastPlayedURL: URL? {
        _ = playback.loadedBook?.url
        _ = playback.isPlaying
        return lastPlayed.lastPlayedURL()
    }

    var body: some View {
        if let book = ContinueCard.book(in: books, lastPlayedURL: lastPlayedURL) {
            LibrarySectionHeader(title: .libraryContinue)
            ContinueCardView(book: book) { onOpen(book) }
        }
    }
}
