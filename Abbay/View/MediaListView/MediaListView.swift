//
//  ContentView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 14/06/23.
//

import SwiftUI

struct MediaListView: View {
    // MARK: - States
    @StateObject
    var model = MediaListViewModel()
    @StateObject
    private var search = LibrarySearchViewModel.makeDefault()
    @State
    private var isSearchPresented = false
    @State
    private var isBrowsing = false

    // MARK: - Body
    var body: some View {
        NavigationView {
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
                .sheet(isPresented: $model.isShowingPlayer) {
                    if let file = model.tappedAudio {
                        PlayerView(file)
                    }
                }
                .backgroundColor(ColorConstants.background.value)
                .foregroundColor(ColorConstants.white.value)
                .onReceive(model.$audioList) { search.update(library: $0) }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
    }

    // MARK: - Toolbar
    var addMenu: some View {
        Menu {
            Button {
                startBrowsing()
            } label: {
                Label(Localizable.browseLibriVox.localized, systemImage: "books.vertical")
            }
            .accessibilityIdentifier(AccessibilityID.Library.menuBrowse)
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

    private func startBrowsing() {
        isBrowsing = true
        if isSearchPresented {
            Task { await search.loadPopular() }
        } else {
            // The search field only exists once the content has switched to its searchable form.
            DispatchQueue.main.async { isSearchPresented = true }
        }
    }

    // MARK: - Content View
    @ViewBuilder
    var contentView: some View {
        if model.audioList.isEmpty && !isBrowsing {
            emptyView
        } else {
            searchableContent
                .searchable(
                    text: $search.query,
                    isPresented: $isSearchPresented,
                    prompt: Localizable.searchPrompt.localized
                )
                .onChange(of: isSearchPresented) { presented in
                    if presented {
                        Task { await search.loadPopular() }
                    } else {
                        isBrowsing = false
                    }
                }
        }
    }

    private var isSearchActive: Bool {
        isSearchPresented || isBrowsing || !search.query.isEmpty
    }

    @ViewBuilder
    private var searchableContent: some View {
        if isSearchActive {
            searchResultsView
        } else {
            ZStack {
                listView
                playerView
            }
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
                startBrowsing()
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
    }

    // MARK: - List View
    @ViewBuilder
    var listView: some View {
        List {
            // `enumerated()` keeps url-based identity while exposing the positional index the
            // accessibility identifiers use.
            ForEach(Array(model.audioList.enumerated()), id: \.element.url) { index, file in
                MediaView(file, namespace: AccessibilityID.Library.row(index))
                .listRowBackground(ColorConstants.background.value)
                .listRowInsets(EdgeInsets())
                .onTapGesture {
                    model.tappedAudio = file
                    model.isShowingPlayer = true
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        model.deleteAudio(file)
                    } label: {
                        Label(Localizable.delete.localized, systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.Library.list)
    }

    // MARK: - Search Results
    private var isQueryEmpty: Bool {
        search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsNoResults: Bool {
        !isQueryEmpty && search.localResults.isEmpty
            && search.remoteStatus == .loaded && search.remoteResults.isEmpty
    }

    @ViewBuilder
    var searchResultsView: some View {
        List {
            if !search.localResults.isEmpty {
                Section(Localizable.inYourLibrary.localized) {
                    ForEach(Array(search.localResults.enumerated()), id: \.element.url) { index, file in
                        localRow(file, index: index)
                    }
                }
            }
            if showsNoResults {
                Text(Localizable.noResults.localized)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(ColorConstants.background.value)
                    .accessibilityIdentifier(AccessibilityID.Library.noResults)
            } else {
                Section(isQueryEmpty ? Localizable.popularOnLibriVox.localized : Localizable.onLibriVox.localized) {
                    remoteSection
                }
            }
        }
        .listStyle(.plain)
    }

    private func localRow(_ file: AudioModel, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MediaView(file, namespace: AccessibilityID.Library.localRow(index))
            if file.isLibriVox {
                Text(Localizable.downloadedTag.localized)
                    .font(.caption)
                    .foregroundColor(ColorConstants.malachite.value)
                    .padding(.horizontal, SpaceConstants.sx16.value)
                    .padding(.bottom, SpaceConstants.sx8.value)
            }
        }
        .listRowBackground(ColorConstants.background.value)
        .listRowInsets(EdgeInsets())
        .onTapGesture {
            model.tappedAudio = file
            model.isShowingPlayer = true
        }
    }

    @ViewBuilder
    private var remoteSection: some View {
        switch search.remoteStatus {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .listRowBackground(ColorConstants.background.value)
        case .offline:
            remoteMessage(Localizable.searchOffline.localized)
        case .failed:
            remoteMessage(Localizable.searchFailed.localized)
        case .loaded:
            ForEach(Array(search.remoteResults.enumerated()), id: \.element.id) { index, book in
                // Task 10 replaces this placeholder with `LibriVoxDetailView`.
                NavigationLink(destination: Text(book.title)) {
                    RemoteBookRow(book: book)
                }
                .listRowBackground(ColorConstants.background.value)
                .accessibilityIdentifier(AccessibilityID.Library.remoteRow(index))
            }
        }
    }

    private func remoteMessage(_ text: String) -> some View {
        Text(text)
            .foregroundColor(ColorConstants.lightSilver.value)
            .frame(maxWidth: .infinity)
            .listRowBackground(ColorConstants.background.value)
            .accessibilityIdentifier(AccessibilityID.Library.searchMessage)
    }

    // MARK: - Player View
    @ViewBuilder
    var playerView: some View {
        if let selectedAudio = model.selectedAudio {
            FloatingPlayerViewFactory.build(selectedAudio)
                .accessibilityIdentifier(AccessibilityID.Library.floatingPlayer)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, SpaceConstants.sx4.value)
                .padding(.bottom, SpaceConstants.sx8.value)
                .onTapGesture {
                    model.tappedAudio = selectedAudio
                    model.isShowingPlayer = true
                }
        }
    }
}

// MARK: - Subviews
private struct RemoteBookRow: View {
    let book: LibriVoxBook

    var body: some View {
        HStack(spacing: SpaceConstants.sx12.value) {
            AsyncImage(url: book.coverURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ColorConstants.onyx.value
            }
            .frame(side: SpaceConstants.sx48.value)
            .cornerRadius(SpaceConstants.sx8.value)
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

// MARK: - Preview
struct MediaListView_Previews: PreviewProvider {
    static var previews: some View {
        MediaListView()
    }
}
