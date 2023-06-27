//
//  FloatingPlayer.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 25/06/23.
//

import SwiftUI

struct FloatingPlayer: View {
    // MARK: States
    @StateObject
    private var model: FloatingPlayerModel

    // MARK: Stored properties
    var player: Player {
        model.player
    }

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
    @ViewBuilder
    var timestamp: some View {
        PlayerProgressView(
            currentTime: $model.currentTime,
            totalTime: model.duration
        )
        .font(.system(size: SpaceConstants.sx12.value))
        .foregroundColor(ColorConstants.white.value)
    }

    @ViewBuilder
    var playerButtons: some View {
        HStack {
            IconButtonView(systemName: "gobackward.15") {
                player.backward(withSeconds: 15)
            }
            IconButtonView(systemName: "gobackward.30") {
                player.backward(withSeconds: 30)
            }
            PlayButtonView(isPlaying: $model.isPlaying) {
                player.play(model.url)
            } onPause: {
                player.pause()
            }
            IconButtonView(systemName: "goforward.15") {
                player.forward(withSeconds: 15)
            }
            IconButtonView(systemName: "goforward.30") {
                player.forward(withSeconds: 30)
            }
        }
        .frame(height: SpaceConstants.sx24.value)
        .foregroundColor(ColorConstants.white.value)
    }

    var body: some View {
        HStack(spacing: SpaceConstants.sx8.value) {
            DataImageView(data: model.imageData)
                .foregroundColor(ColorConstants.white.value)
                .frame(side: SpaceConstants.sx64.value)
                .cornerRadius(8)
            VStack(spacing: SpaceConstants.sx8.value) {
                PlayerTitleView(
                    isPlaying: $model.isPlaying,
                    text: model.title
                )
                .font(.system(size: SpaceConstants.sx16.value))
                .padding(.bottom, SpaceConstants.sx8.value)
                timestamp
                HStack {
                    Spacer()
                    playerButtons
                    Spacer()
                    ChapterCountView(
                        chapter: .constant(0),
                        total: model.chapters.count
                    )
                    .foregroundColor(ColorConstants.white.value)
                }
            }
        }
        .padding(SpaceConstants.sx8.value)
        .background(ColorConstants.onyx.value)
        .cornerRadius(SpaceConstants.sx8.value)
        .shadow(radius: SpaceConstants.sx40.value)
    }
}

// MARK: - Preview
struct FloatingPlayer_Previews: PreviewProvider {
    static var previews: some View {
        FloatingPlayer(
            AudioModel(
                title: "title",
                albumName: "album name",
                artist: "",
                duration: 48657, chapters: ["1", "2", "3"]
            )
        )
        .padding(.horizontal, SpaceConstants.sx4.value)
    }
}
