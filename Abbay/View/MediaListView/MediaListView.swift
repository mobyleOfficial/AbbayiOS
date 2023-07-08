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
                .navigationTitle("Your Audiobooks")
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        IconButtonView(systemName: "magnifyingglass")
                        IconButtonView(systemName: "plus.rectangle.on.folder") {
                            model.isShowingFilePicker = true
                        }
                        IconButtonView(systemName: "gearshape")
                    }
                }
                .sheet(isPresented: $model.isShowingFilePicker) {
                    DocumentPickerView(selectedFiles: $model.audioList, fileLoader: model.fileLoader)
                }
                .backgroundColor(ColorConstants.background.value)
                .foregroundColor(ColorConstants.white.value)
        }
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
            Text("So empty...")
        }
    }

    // MARK: - List View
    @ViewBuilder
    var listView: some View {
        List {
            ForEach(model.audioList, id: \.url) { file in
                MediaView(
                    file,
                    player: model.player,
                    onSelection: model.mediaSelection
                )
                .backgroundColor(ColorConstants.background.value)
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Player View
    @ViewBuilder
    var playerView: some View {
        if let selectedAudio = model.selectedAudio {
            FloatingPlayerView(selectedAudio, player: model.player)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, SpaceConstants.sx4.value)
                .padding(.bottom, SpaceConstants.sx8.value)
        }
    }
}

// MARK: - Preview
struct MediaListView_Previews: PreviewProvider {
    static var previews: some View {
        MediaListView()
    }
}
