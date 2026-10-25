//
//  LibriVoxSearchView.swift
//  Abbay
//

import SwiftUI

/// The Search tab: popular books as cards, or LibriVox results for the typed query.
struct LibriVoxSearchView: View {
    let onOpen: (LibriVoxBook) -> Void

    @State
    private var model = LibriVoxSearchViewModel.makeDefault()

    init(onOpen: @escaping (LibriVoxBook) -> Void) {
        self.onOpen = onOpen
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .backgroundColor(ColorConstants.background.value)
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
            Color.clear
        case .loading:
            ProgressView()
                .padding(.top, SpaceConstants.sx48.value)
        case .offline:
            message(Localizable.searchOffline.localized)
        case .failed:
            message(Localizable.searchFailed.localized)
        case .loaded:
            if isQueryEmpty {
                popularGrid
            } else if model.results.isEmpty {
                Text(Localizable.noResults.localized)
                    .padding(.top, SpaceConstants.sx48.value)
                    .accessibilityIdentifier(AccessibilityID.Search.noResults)
            } else {
                resultsList
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundColor(ColorConstants.lightSilver.value)
            .padding(.top, SpaceConstants.sx48.value)
            .accessibilityIdentifier(AccessibilityID.Search.message)
    }

    private var popularGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpaceConstants.sx12.value) {
                Text(Localizable.popularOnLibriVox.localized)
                    .font(.title3.bold())
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: SpaceConstants.sx16.value), GridItem(.flexible())],
                    spacing: SpaceConstants.sx16.value
                ) {
                    ForEach(Array(model.popular.enumerated()), id: \.element.id) { index, book in
                        Button {
                            onOpen(book)
                        } label: {
                            LibriVoxBookCard(book: book)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(AccessibilityID.Search.card(index))
                    }
                }
            }
            .padding(.horizontal, SpaceConstants.sx16.value)
        }
    }

    private var resultsList: some View {
        List {
            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, book in
                Button {
                    onOpen(book)
                } label: {
                    LibriVoxBookRow(book: book)
                }
                .listRowBackground(ColorConstants.background.value)
                .accessibilityIdentifier(AccessibilityID.Search.result(index))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct LibriVoxBookCard: View {
    let book: LibriVoxBook

    var body: some View {
        VStack(alignment: .leading, spacing: SpaceConstants.sx8.value) {
            ArtworkView(url: book.coverURL)
                .aspectRatio(1, contentMode: .fit)
            Text(book.title)
                .font(.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundColor(ColorConstants.white.value)
    }
}

/// A LibriVox search result.
struct LibriVoxBookRow: View {
    let book: LibriVoxBook

    var body: some View {
        HStack(spacing: SpaceConstants.sx12.value) {
            ArtworkView(url: book.coverURL)
                .frame(side: SpaceConstants.sx48.value)
            VStack(alignment: .leading) {
                Text(book.title)
                    .lineLimit(2)
                Text(book.authors)
                    .font(.caption)
                    .foregroundColor(ColorConstants.lightSilver.value)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "arrow.down.circle")
                .foregroundColor(ColorConstants.malachite.value)
        }
        .foregroundColor(ColorConstants.white.value)
    }
}
