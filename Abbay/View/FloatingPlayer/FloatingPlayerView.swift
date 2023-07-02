//
//  FloatingPlayer.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 25/06/23.
//

import SwiftUI

struct FloatingPlayerView: View {
    // MARK: States
    @ObservedObject
    private var model: FloatingPlayerViewModel

    // MARK: Stored properties
    private var info: AudioModel {
        model.info
    }

    // MARK: - Init
    init(_ audioModel: AudioModel, player: PlayerProtocol) {
        _model = .init(
            wrappedValue: .init(
                audioModel,
                player: player
            )
        )
    }

    // MARK: - Body
    @ViewBuilder
    var timestamp: some View {
        PlayerProgressView(
            currentTime: $model.currentTime,
            totalTime: info.duration
        )
        .font(.system(size: SpaceConstants.sx12.value))
        .foregroundColor(ColorConstants.white.value)
    }

    @ViewBuilder
    var playerButtons: some View {
        HStack {
            IconButtonView(systemName: "gobackward.30") {
                model.backward(withSeconds: 30)
            }
            IconButtonView(systemName: "gobackward.15") {
                model.backward(withSeconds: 15)
            }
            PlayButtonView(isPlaying: $model.isPlaying) {
                model.play()
            } onPause: {
                model.pause()
            }
            IconButtonView(systemName: "goforward.15") {
                model.forward(withSeconds: 15)
            }
            IconButtonView(systemName: "goforward.30") {
                model.forward(withSeconds: 30)
            }
        }
        .frame(height: SpaceConstants.sx24.value)
        .foregroundColor(ColorConstants.white.value)
    }

    var body: some View {
        HStack(spacing: SpaceConstants.sx8.value) {
            DataImageView(data: info.imageData)
                .foregroundColor(ColorConstants.white.value)
                .frame(side: SpaceConstants.sx72.value)
                .cornerRadius(SpaceConstants.sx8.value)
            VStack(spacing: SpaceConstants.sx8.value) {
                PlayerTitleView(
                    isPlaying: $model.isPlaying,
                    text: info.title
                )
                .font(.system(size: SpaceConstants.sx16.value))
                timestamp
                HStack {
                    Spacer()
                    playerButtons
                    Spacer()
                    ChapterCountView(
                        chapter: $model.currentChapter,
                        total: info.chapters.count + 1
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
        FloatingPlayerView(
            AudioModel(
                title: "title",
                albumName: "album name",
                artist: "",
                duration: 48657,
                chapters: [ChapterModel].init(
                    repeating: ChapterModel(),
                    count: 3
                )
            ),
            player: Player()
        )
        .padding(.horizontal, SpaceConstants.sx4.value)
    }
}
