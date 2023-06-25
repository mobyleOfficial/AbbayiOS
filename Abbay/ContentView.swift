//
//  ContentView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 14/06/23.
//

import SwiftUI

struct ContentView: View {
    @State
    var presenting = false

    @State
    var files = [AudioModel]()

    @ViewBuilder
    var content: some View {
        if files.isEmpty {
            VStack {
                Image(systemName: "folder.badge.questionmark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: SpaceConstants.sx32.value)
                Text("So empty...")
            }
        } else {
            List {
                ForEach(files, id: \.url) { file in
                    MediaView(model: file)
                        .backgroundColor(ColorConstants.background.value)
                        .listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.plain)
        }
    }

    var body: some View {
        NavigationView {
            content
            .navigationTitle("Your Audiobooks")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Image(systemName: "magnifyingglass")
                    Image(systemName: "plus.rectangle.on.folder")
                        .onTapGesture {
                            presenting = true
                        }
                    Image(systemName: "gearshape")
                }
            }
            .sheet(isPresented: $presenting) {
                DocumentPickerView(selectedFiles: $files, fileLoader: FileLoader())
            }
            .backgroundColor(ColorConstants.background.value)
            .foregroundColor(ColorConstants.white.value)
        }
        .preferredColorScheme(.dark)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
