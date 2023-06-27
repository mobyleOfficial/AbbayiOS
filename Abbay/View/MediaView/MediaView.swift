//
//  MediaView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 21/06/23.
//

import SwiftUI

struct MediaView: View {
    // MARK: - States
    @StateObject
    private var model: MediaViewModel

    // MARK: - Init
    init(_ audioModel: AudioModel) {
        _model = .init(
            wrappedValue: .init(
                title: audioModel.title,
                duration: audioModel.duration,
                imageData: audioModel.imageData,
                url: audioModel.url,
                chapters: audioModel.chapters
            )
        )
    }

    // MARK: - Body
    var body: some View {
        HStack {
            DataImageView(data: model.imageData)
                .frame(side: SpaceConstants.sx64.value)
                .foregroundColor(ColorConstants.white.value)
                .cornerRadius(SpaceConstants.sx8.value)
            Spacer()
            VStack(alignment: .leading) {
                PlayerTitleView(isPlaying: $model.isPlaying, text: model.title)
                    .font(.system(size: SpaceConstants.sx16.value))
                    .padding(.bottom, SpaceConstants.sx8.value)
                HStack {
                    ChapterCountView(chapter: .constant(0), total: model.chapters.count)
                    Spacer()
                    TimestampView(current: $model.currentTime, total: model.duration)
                }
            }
            PlayButtonView(isPlaying: $model.isPlaying) {
                model.player.play(model.url)
            } onPause: {
                model.player.pause()
            }
            .frame(height: SpaceConstants.sx24.value)
            .padding(.leading, SpaceConstants.sx8.value)
        }
        .foregroundColor(ColorConstants.white.value)
        .padding(SpaceConstants.sx16.value)
    }
}

// MARK: - Preview
struct MediaView_Previews: PreviewProvider {
    static var previews: some View {
        MediaView(
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
