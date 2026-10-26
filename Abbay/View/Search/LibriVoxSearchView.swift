//
//  LibriVoxSearchView.swift
//  Abbay
//

import SwiftUI

/// The Search tab (#166 G4): popular books in a uniform grid of square covers, or LibriVox results
/// for the typed query as rows with a GET pill. Every other state is a system empty-state view.
struct LibriVoxSearchView: View {
    let onOpen: (LibriVoxBook) -> Void
    /// The LibriVox ids of the books already in the library: their result rows say Open, not GET.
    let libraryBookIDs: Set<String>

    @State
    private var model = LibriVoxSearchViewModel.makeDefault()

    init(libraryBookIDs: Set<String> = [], onOpen: @escaping (LibriVoxBook) -> Void) {
        self.libraryBookIDs = libraryBookIDs
        self.onOpen = onOpen
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { ColorConstants.background.value.ignoresSafeArea() }
            .foregroundColor(ColorConstants.white.value)
            .navigationTitle(Localizable.searchTitle.localized)
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $model.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Localizable.librivoxSearchPrompt.localized
            )
            .task { await model.loadPopular() }
    }

    private var isQueryEmpty: Bool {
        model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var content: some View {
        switch model.status {
        case .idle:
            unavailable(
                title: Localizable.searchIdleTitle.localized,
                systemImage: "books.vertical",
                message: Localizable.searchIdleMessage.localized
            )
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .offline:
            unavailable(
                title: Localizable.searchOfflineTitle.localized,
                systemImage: "wifi.slash",
                message: Localizable.searchOffline.localized,
                messageIdentifier: AccessibilityID.Search.message
            )
        case .failed:
            unavailable(
                title: Localizable.searchFailedTitle.localized,
                systemImage: "exclamationmark.triangle",
                message: Localizable.searchFailed.localized,
                messageIdentifier: AccessibilityID.Search.message
            )
        case .loaded:
            if isQueryEmpty {
                popularGrid
            } else if model.results.isEmpty {
                unavailable(
                    title: Localizable.noResults.localized,
                    systemImage: "magnifyingglass",
                    message: Localizable.searchNoResultsHint.localized,
                    titleIdentifier: AccessibilityID.Search.noResults
                )
            } else {
                resultsList
            }
        }
    }

    /// The system empty state. Identifiers go on the texts, which are leaves.
    private func unavailable(
        title: String,
        systemImage: String,
        message: String,
        titleIdentifier: String? = nil,
        messageIdentifier: String? = nil
    ) -> some View {
        ContentUnavailableView {
            Label {
                Text(title)
                    .identifier(ifPresent: titleIdentifier)
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            Text(message)
                .foregroundColor(ColorConstants.lightSilver.value)
                .identifier(ifPresent: messageIdentifier)
        }
    }

    // MARK: - Popular

    /// Three columns on an iPhone; more on a wider screen. Every cell has the same shape.
    private static let gridColumns = [
        GridItem(
            .adaptive(minimum: SearchMetrics.cellMinimumWidth, maximum: SearchMetrics.cellMaximumWidth),
            spacing: SearchMetrics.gridSpacing,
            alignment: .top
        )
    ]

    private var popularGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpaceConstants.sx12.value) {
                Text(Localizable.popularOnLibriVox.localized)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: Self.gridColumns, alignment: .leading, spacing: SpaceConstants.sx20.value) {
                    ForEach(Array(model.popular.enumerated()), id: \.element.id) { index, book in
                        Button {
                            onOpen(book)
                        } label: {
                            LibriVoxBookCell(book: book)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(AccessibilityID.Search.card(index))
                    }
                }
            }
            .padding(.horizontal, SpaceConstants.sx16.value)
            .padding(.bottom, SpaceConstants.sx24.value)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.results.enumerated()), id: \.element.id) { index, book in
                    Button {
                        onOpen(book)
                    } label: {
                        LibriVoxBookRow(
                            book: book,
                            action: LibriVoxBookRow.action(for: book, libraryBookIDs: libraryBookIDs)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityID.Search.result(index))
                    Divider()
                        .padding(.leading, SearchMetrics.rowCover + SpaceConstants.sx12.value)
                }
            }
            .padding(.horizontal, SpaceConstants.sx16.value)
            .padding(.bottom, SpaceConstants.sx24.value)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

private enum SearchMetrics {
    static let cellMinimumWidth: CGFloat = 100
    static let cellMaximumWidth: CGFloat = 180
    static let gridSpacing: CGFloat = SpaceConstants.sx12.value
    static let rowCover: CGFloat = SpaceConstants.sx48.value
}

/// A Popular cell: a square cover, the title in a fixed two-line box and the author, so every
/// cell in a row has the same height whatever its title.
private struct LibriVoxBookCell: View {
    let book: LibriVoxBook

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceConstants.sx4.value) {
            ArtworkView(url: book.coverURL)
                .aspectRatio(1, contentMode: .fit)
                .padding(.bottom, SpaceConstants.sx4.value)
            Text(book.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text(book.authors)
                .font(.caption)
                .foregroundColor(ColorConstants.lightSilver.value)
                .lineLimit(1)
        }
        .foregroundColor(ColorConstants.white.value)
        .contentShape(Rectangle())
    }
}

/// A LibriVox search result: the cover, the title and the author, and a glass pill that says what a
/// tap does. Search results carry no duration, so the line is the author only.
struct LibriVoxBookRow: View {
    /// The pill's word. Tapping it or the row opens the book page either way; GET never starts a
    /// download from the list.
    enum Action: Equatable {
        /// Not in the library yet.
        case get
        /// Already in the library.
        case open

        var title: String {
            switch self {
            case .get: Localizable.getBook.localized
            case .open: Localizable.openBook.localized
            }
        }
    }

    let book: LibriVoxBook
    let action: Action

    static func action(for book: LibriVoxBook, libraryBookIDs: Set<String>) -> Action {
        libraryBookIDs.contains(book.id) ? .open : .get
    }

    var body: some View {
        HStack(spacing: SpaceConstants.sx12.value) {
            ArtworkView(url: book.coverURL)
                .frame(side: SearchMetrics.rowCover)
            VStack(alignment: .leading, spacing: SpaceConstants.sx2.value) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(book.authors)
                    .font(.caption)
                    .foregroundColor(ColorConstants.lightSilver.value)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(action.title)
                .font(.footnote.bold())
                .foregroundColor(ColorConstants.malachite.value)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, SpaceConstants.sx16.value)
                .padding(.vertical, SpaceConstants.sx4.value + SpaceConstants.sx2.value)
                .abbayGlass(in: Capsule())
        }
        .padding(.vertical, SpaceConstants.sx8.value)
        .foregroundColor(ColorConstants.white.value)
        .contentShape(Rectangle())
    }
}

private extension View {
    @ViewBuilder
    func identifier(ifPresent identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
