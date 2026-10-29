//
//  ContentView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 14/06/23.
//

import SwiftUI
import UniformTypeIdentifiers

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
    /// Switches to the Search tab (the empty state's primary button and the + menu's Download).
    let onBrowse: () -> Void
    /// Opens the Settings sheet, which the root presents.
    var onSettings: VoidCallback?

    @Environment(PlayerPresentation.self)
    private var presentation
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    @State
    private var query = ""
    /// The grid's own width: its columns follow the room it has (#255, #251), not the screen's.
    @State
    private var gridWidth: CGFloat = 0
    /// The book at the top of the grid's visible area (its cells' ids are their URLs), kept as the
    /// user scrolls, so a change in the column count can bring it back (#267).
    @State
    private var topBook: URL??
    /// `topBook` as it was before the grid started changing width. While the width animates (the
    /// player pane sliding in, a fold), every frame moves the cells and `topBook` with them.
    @State
    private var anchorBook: URL??
    /// The column count when the current resize began; nil while the width is settled.
    @State
    private var resizeStartColumns: Int?
    @State
    private var resizeGeneration = 0
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
            // The system presents its own picker (open in place, several audio files). On a regular
            // width it is a centred form sheet; on iOS 27.1 the Files picker still draws its first
            // frame at phone width against the left edge, however it is presented (full screen too).
            .fileImporter(
                isPresented: $model.isShowingFilePicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                guard case let .success(urls) = result, !urls.isEmpty else { return }
                Task { await model.importAudio(from: urls) }
            }

            .foregroundColor(ColorConstants.white.value)
    }

    // MARK: - Toolbar
    /// Import file, and Download, which only switches to the Search tab (where LibriVox lives).
    var addMenu: some View {
        Menu {
            Button {
                model.startImport()
            } label: {
                Label(Localizable.importFile.localized, systemImage: "folder.badge.plus")
            }
            .accessibilityIdentifier(AccessibilityID.Library.menuImport)
            Button {
                onBrowse()
            } label: {
                Label(Localizable.download.localized, systemImage: "arrow.down.circle")
            }
            .accessibilityIdentifier(AccessibilityID.Library.menuDownload)
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

    /// As many columns as fit the grid's width at this text size (`LibraryGridLayout`): three on a
    /// phone at the default size, more in a wide pane or window.
    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: SpaceConstants.sx12.value, alignment: .top),
            count: columnCount
        )
    }

    private var columnCount: Int {
        LibraryGridLayout.columnCount(width: gridWidth, dynamicTypeSize: dynamicTypeSize)
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: SpaceConstants.sx8.value) {
                        if !isSearching {
                            ContinueSection(books: model.audioList, lastPlayed: lastPlayed) { book in
                                // Grows out of the card's cover (#241).
                                presentation.open(book, animated: true, from: .continueCard(book))
                            }
                            LibrarySectionHeader(title: .libraryAllBooks)
                        }
                        grid(books)
                    }
                    .padding(.horizontal, SpaceConstants.sx16.value)
                    .padding(.bottom, SpaceConstants.sx16.value)
                }
                // The grid's width is the scroll view's minus the margins: measured on the scroll
                // view, which doesn't depend on the grid. Measured on the grid (whose width follows
                // its own columns), iOS 17 kept a narrow first value: one column of phone-wide
                // covers on the iPhone SE (#278).
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .onChange(of: geometry.size.width, initial: true) { _, width in
                                widthChanged(to: max(width - 2 * SpaceConstants.sx16.value, 0))
                            }
                    }
                }
                .scrollPosition(id: $topBook)
                .onChange(of: topBook) {
                    if resizeStartColumns == nil { anchorBook = topBook }
                }
                // A fold, a rotation, a resize or the player pane opening changes the column count,
                // which moves every cell: once the width settles, the book that was at the top
                // before the resize goes back there (#267).
                .onChange(of: resizeStartColumns) { start, settled in
                    guard settled == nil, let start, start != columnCount,
                          let anchorBook, let id = anchorBook,
                          let index = books.firstIndex(where: { $0.url == id }),
                          LibraryGridLayout.restoresTopBook(at: index, oldColumnCount: start) else { return }
                    proxy.scrollTo(id, anchor: .top)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Library.list)
        }
    }

    private func grid(_ books: [AudioModel]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: LibraryGridLayout.rowSpacing) {
            // `enumerated()` keeps url-based identity while exposing the positional index the
            // accessibility identifiers use.
            ForEach(Array(books.enumerated()), id: \.element.url) { index, file in
                MediaView(
                    file,
                    namespace: AccessibilityID.Library.row(index),
                    // As before: while searching, a fully downloaded LibriVox book says so.
                    showsDownloadedBadge: isSearching,
                    // Grows out of the cell's cover (#241).
                    onOpen: { presentation.open(file, animated: true, from: .cell(file)) },
                    onDelete: { model.deleteAudio(file) }
                )
            }
        }
        .scrollTargetLayout()
    }

    /// Marks a resize in progress, and its end once the width has held still for a moment.
    private func widthChanged(to width: CGFloat) {
        if resizeStartColumns == nil { resizeStartColumns = columnCount }
        gridWidth = width
        resizeGeneration += 1
        let generation = resizeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + LibraryGridLayout.resizeSettleDelay) {
            guard generation == resizeGeneration else { return }
            resizeStartColumns = nil
        }
    }
}

// MARK: - Grid layout

/// How many cover columns the library grid has. Pure, so it is unit tested. A cover needs about
/// `minCellWidth` for its two-line title at the default text size; more at larger sizes (two
/// columns on a phone from *xLarge* up, as before). Wide grids ask for larger covers, so an iPad or
/// the unfolded iPhone Duo shows bigger covers rather than a long row of thumbnails.
enum LibraryGridLayout {
    static let columnSpacing: CGFloat = SpaceConstants.sx12.value
    static let rowSpacing: CGFloat = SpaceConstants.sx16.value
    /// Past this width the covers grow (`wideCellWidth`).
    static let wideGridWidth: CGFloat = 600
    static let minCellWidth: CGFloat = 104
    static let wideCellWidth: CGFloat = 150

    /// Before the grid has been measured (`width` 0) it assumes a phone's three columns.
    static func columnCount(width: CGFloat, dynamicTypeSize: DynamicTypeSize) -> Int {
        guard width > 0 else { return dynamicTypeSize >= .xLarge ? 2 : 3 }
        let base = width > wideGridWidth ? wideCellWidth : minCellWidth
        let cell = base * cellScale(dynamicTypeSize)
        let fits = Int((width + columnSpacing) / (cell + columnSpacing))
        return max(fits, 1)
    }

    /// Whether a column change should scroll the top book back into place: only once the user has
    /// scrolled past the first row. In the first row, the top of the library (the Continue card,
    /// the header) stays in view instead.
    /// How long the grid's width must hold still before a resize counts as over (a pane's spring
    /// takes about 0.35 s).
    static let resizeSettleDelay: TimeInterval = 0.45

    static func restoresTopBook(at index: Int, oldColumnCount: Int) -> Bool {
        index >= oldColumnCount
    }

    /// *xLarge* to *xxxLarge* titles need about a third more; accessibility sizes half again.
    static func cellScale(_ size: DynamicTypeSize) -> CGFloat {
        if size.isAccessibilitySize { return 1.5 }
        if size >= .xLarge { return 1.4 }
        return 1
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
