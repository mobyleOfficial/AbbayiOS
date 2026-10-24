//
//  ContentView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 14/06/23.
//

import SwiftUI

/// The Library tab: the books in the library, a local-only search over them, the empty state and
/// the toolbar. The root owns the model and the tab's `NavigationStack`; LibriVox lives in the
/// Search tab.
struct MediaListView: View {
    // MARK: - Properties
    @ObservedObject
    var model: MediaListViewModel
    /// Switches to the Search tab (the empty state's primary button).
    let onBrowse: () -> Void

    @Environment(PlayerPresentation.self)
    private var presentation
    @State
    private var query = ""

    // MARK: - Body
    var body: some View {
        contentView
            .navigationTitle(Localizable.libraryTitle.localized)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    addMenu
                    // Settings is out of scope: same behavior as before (no action), but a
                    // real `Button` so the system sizes it like the add menu.
                    Button {
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier(AccessibilityID.Library.toolbarSettings)
                }
            }
            .sheet(isPresented: $model.isShowingFilePicker) {
                DocumentPickerView(onImport: { urls in
                    await model.importAudio(from: urls)
                })
            }
            .backgroundColor(ColorConstants.background.value)
            .foregroundColor(ColorConstants.white.value)
    }

    // MARK: - Toolbar
    /// Only Import file: the Search tab replaced "Browse LibriVox".
    var addMenu: some View {
        Menu {
            Button {
                model.isShowingFilePicker = true
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
            listView
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Localizable.librarySearchPrompt.localized
            )
        }
    }

    // MARK: - Empty View
    @ViewBuilder
    var emptyView: some View {
        VStack(spacing: SpaceConstants.sx16.value) {
            Image(systemName: "folder.badge.questionmark")
                .resizable()
                .scaledToFit()
                .frame(width: SpaceConstants.sx32.value)
            Text(Localizable.emptyLibraryTitle.localized)
                .accessibilityIdentifier(AccessibilityID.Library.empty)
            Button {
                onBrowse()
            } label: {
                Text(Localizable.browseFreeAudiobooks.localized)
            }
            .buttonStyle(LibraryActionButtonStyle(isPrimary: true))
            .accessibilityIdentifier(AccessibilityID.Library.emptyBrowse)
            Button {
                model.isShowingFilePicker = true
            } label: {
                Text(Localizable.importAFile.localized)
            }
            .buttonStyle(LibraryActionButtonStyle(isPrimary: false))
            .accessibilityIdentifier(AccessibilityID.Library.emptyImport)
        }
        .padding(.horizontal, SpaceConstants.sx32.value)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List View
    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    var listView: some View {
        let books = LibraryFilter.filter(model.audioList, query: query)
        List {
            // `enumerated()` keeps url-based identity while exposing the positional index the
            // accessibility identifiers use.
            ForEach(Array(books.enumerated()), id: \.element.url) { index, file in
                VStack(alignment: .leading, spacing: 0) {
                    MediaView(file, namespace: AccessibilityID.Library.row(index))
                    // As before: while searching, a fully downloaded LibriVox book says so.
                    if isSearching {
                        DownloadedTag(book: file)
                    }
                }
                .listRowBackground(ColorConstants.background.value)
                .listRowInsets(EdgeInsets())
                .onTapGesture {
                    presentation.open(file, animated: true)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        model.deleteAudio(file)
                    } label: {
                        Label(Localizable.delete.localized, systemImage: "trash")
                    }
                }
            }
            if books.isEmpty {
                Text(Localizable.noResults.localized)
                    .foregroundColor(ColorConstants.lightSilver.value)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(ColorConstants.background.value)
                    .accessibilityIdentifier(AccessibilityID.Library.noResults)
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.Library.list)
    }
}

// MARK: - Subviews
/// "Downloaded" under a LibriVox book whose chapters are all on disk. Reads only its own book's
/// download entry.
private struct DownloadedTag: View {
    let book: AudioModel

    @Environment(\.downloadStateStore)
    private var downloads

    var body: some View {
        let state = book.librivoxID.flatMap { downloads?.entry(for: $0).state }
        if LibriVoxIdentity.isFullyDownloaded(book, state: state) {
            Text(Localizable.downloadedTag.localized)
                .font(.caption)
                .foregroundColor(ColorConstants.malachite.value)
                .padding(.horizontal, SpaceConstants.sx16.value)
                .padding(.bottom, SpaceConstants.sx8.value)
        }
    }
}

private struct LibraryActionButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(isPrimary ? ColorConstants.background2.value : ColorConstants.white.value)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpaceConstants.sx16.value)
            .background(isPrimary ? ColorConstants.malachite.value : ColorConstants.onyx.value)
            .cornerRadius(SpaceConstants.sx12.value)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
