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
    init(
        _ audioModel: AudioModel,
        player: PlayerProtocol
    ) {
        _model = .init(
            wrappedValue: .init(
                audioModel,
                player: player
            )
        )
    }

    // MARK: - Body
    var body: some View {
        HStack {
            DataImageView(data: model.info.imageData)
                .frame(side: SpaceConstants.sx64.value)
                .foregroundColor(ColorConstants.white.value)
                .cornerRadius(SpaceConstants.sx8.value)
            Spacer()
            VStack(alignment: .leading) {
                PlayerTitleView(
                    isPlaying: $model.isPlaying,
                    text: model.info.title
                )
                .font(.system(size: SpaceConstants.sx16.value))
                .padding(.bottom, SpaceConstants.sx8.value)
                HStack {
                    ChapterCountView(
                        chapter: $model.currentChapter,
                        total: model.info.chapters.count
                    )
                    Spacer()
                    TimestampView(current: $model.currentTime, total: model.info.duration)
                }
            }
            PlayButtonView(isPlaying: $model.isPlaying) {
                model.play()
            } onPause: {
                model.pause()
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
                duration: 48_657,
                chapters: [ChapterModel].init(
                    repeating: ChapterModel(),
                    count: 3
                )
            ),
            player: Player()
        )
        .backgroundColor(ColorConstants.background.value)
    }
}
