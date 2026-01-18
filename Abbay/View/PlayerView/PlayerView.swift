//
//  PlayerView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 10/07/23.
//

import SwiftUI

struct PlayerView: View {
    // MARK: - Properties
    @StateObject
    private var model: PlayerViewModel

    // MARK: - Inits
    init(_ audioModel: AudioModel) {
        self._model = .init(wrappedValue: .init(audioModel))
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: SpaceConstants.sx16.value) {
            topButtonsView
            coverView
            playerView
            chaptersView
        }
        .padding(.horizontal, SpaceConstants.sx32.value)
        .backgroundColor(ColorConstants.onyx.value)
    }

    // MARK: - Top buttons
    @ViewBuilder
    private var topButtonsView: some View {
        Rectangle()
            .foregroundColor(ColorConstants.spanishGray.value)
            .frame(
                width: SpaceConstants.sx24.value,
                height: SpaceConstants.sx2.value
            )
            .padding(SpaceConstants.sx8.value)
    }

    // MARK: - Cover view
    @ViewBuilder
    private var coverView: some View {
        VStack {
            DataImageView(data: model.info.imageData)
                .scaledToFit()
                .cornerRadius(SpaceConstants.sx32.value)
                .frame(side: SpaceConstants.sx72.value * SpaceConstants.sx4.value)
            PlayerTitleView(
                isPlaying: $model.isPlaying,
                text: model.info.title,
                alignment: .center
            )
            .font(.system(size: SpaceConstants.sx24.value))
        }
    }

    // MARK: - Player buttons
    @ViewBuilder
    private var playerButtonsView: some View {
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
        .frame(height: SpaceConstants.sx32.value)
        .foregroundColor(ColorConstants.white.value)
    }

    // MARK: - Timestamp
    @ViewBuilder
    private var timestamp: some View {
        PlayerProgressView(
            currentTime: $model.currentTime,
            totalTime: model.info.duration,
            onStartUpdate: {
                model.willSeek()
            },
            onFinishUpdate: { time in
                model.seek(time)
            }
        )
        .font(.system(size: SpaceConstants.sx16.value))
        .foregroundColor(ColorConstants.white.value)
        .onChange(of: model.currentTime) { time in
            model.setCurrentChapter(for: time)
        }
    }

    // MARK: - Player view
    @ViewBuilder
    private var playerView: some View {
        VStack(spacing: SpaceConstants.sx24.value) {
            playerButtonsView
            timestamp
        }
    }

    @ViewBuilder
    private var chaptersView: some View {
        VStack {
            let listSpacing = SpaceConstants.sx16.value
            HStack {
                Text(Localizable.chapterSelectionTitle.localized)
                    .foregroundColor(ColorConstants.white.value)
                    .font(.system(size: SpaceConstants.sx16.value))
                Spacer()
            }
            .padding(listSpacing)
            .background(ColorConstants.background2.value)
            List {
                ForEach(Array(model.info.chapters.enumerated()), id: \.offset) { index, chapter in
                    PlayerTitleView(
                        isPlaying: .constant(model.currentChapter == index),
                        text: chapter.title
                    )
                    .contentShape(Rectangle())
                    .listRowBackground(ColorConstants.clear.value)
                    .listRowInsets(.init(all: listSpacing))
                    .font(.system(size: SpaceConstants.sx16.value))
                    .onTapGesture {
                        model.willSeek()
                        model.seek(chapter.startTime)
                    }
                }
            }
            .listStyle(.plain)
            .disabled(!model.isPlaying)
        }
        .background(ColorConstants.background.value)
        .cornerRadius(SpaceConstants.sx32.value)
        .opacity(model.isPlaying ? 1.0 : 0.5)
    }
}

// MARK: - Preview
struct PlayerView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerView(
            AudioModel(
                title: "title",
                albumName: "album name",
                artist: "",
                duration: 48_657,
                chapters: [ChapterModel].init(
                    repeating: ChapterModel(title: "Chapter"),
                    count: 3
                )
            )
        )
    }
}
