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

    // MARK: - Body
    var body: some View {
        NavigationView {
            contentView
                .navigationTitle(Localizable.libraryTitle.localized)
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        IconButtonView(systemName: "magnifyingglass")
                            .accessibilityIdentifier(AccessibilityID.Library.toolbarSearch)
                        IconButtonView(systemName: "plus.rectangle.on.folder") {
                            model.isShowingFilePicker = true
                        }
                        .accessibilityIdentifier(AccessibilityID.Library.toolbarImport)
                        IconButtonView(systemName: "gearshape")
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
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
    }

    // MARK: - Content View
    @ViewBuilder
    var contentView: some View {
        if model.audioList.isEmpty {
            emptyView
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
        VStack {
            Image(systemName: "folder.badge.questionmark")
                .resizable()
                .scaledToFit()
                .frame(width: SpaceConstants.sx32.value)
            Text(Localizable.emptyLibraryTitle.localized)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Library.empty)
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

// MARK: - Preview
struct MediaListView_Previews: PreviewProvider {
    static var previews: some View {
        MediaListView()
    }
}
