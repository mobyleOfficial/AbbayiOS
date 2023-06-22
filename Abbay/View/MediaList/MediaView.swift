//
//  MediaView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 21/06/23.
//

import SwiftUI

struct MediaView: View {

    var model: AudioModel

    @ViewBuilder
    var image: some View {
        if let data = model.imageData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
        } else {
            Image(systemName: "photo")
                .resizable()
        }
    }

    var body: some View {
        HStack {
            image
                .frame(side: SpaceConstants.sx64.value)
                .cornerRadius(8)
            Spacer()
            VStack(alignment: .leading) {
                Text(model.title)
                    .font(.system(size: SpaceConstants.sx16.value))
                    .padding(.bottom, SpaceConstants.sx8.value)
                HStack {
                    HStack {
                        Image(systemName: "book.closed")
                        Text("0/\(model.chapters.count)")
                    }
                    Spacer()
                    HStack {
                        Image(systemName: "clock")
                        Text("\(0.timestamp)/\(model.duration.timestamp)")
                    }
                }
            }
            Image(systemName: "play.fill")
                .frame(side: SpaceConstants.sx24.value)
                .padding(.leading, SpaceConstants.sx8.value)
        }
        .foregroundColor(ColorConstants.white.value)
        .padding(SpaceConstants.sx16.value)
    }
}

struct MediaView_Previews: PreviewProvider {
    static var previews: some View {
        MediaView(
            model:
                AudioModel(
                    title: "title",
                    albumName: "album name",
                    artist: "",
                    duration: 48657, chapters: ["1", "2", "3"]
                )
        )
        .backgroundColor(ColorConstants.background.value)
    }
}
