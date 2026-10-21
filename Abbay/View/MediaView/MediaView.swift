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

    // MARK: - Stored properties
    /// Accessibility namespace supplied by the owner, so the same row component can appear on
    /// several screens without identifier collisions.
    private let namespace: String

    // MARK: - Init
    init(_ audioModel: AudioModel, namespace: String = "media") {
        _model = .init(wrappedValue: .init(audioModel))
        self.namespace = namespace
    }

    // MARK: - Body
    var body: some View {
        HStack {
            DataImageView(data: model.info.imageData)
                .accessibilityIdentifier(AccessibilityID.Element.artwork(namespace))
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
                .accessibilityIdentifier(AccessibilityID.Element.title(namespace))
                HStack {
                    ChapterCountView(
                        chapter: $model.currentChapter,
                        total: model.info.chapters.count
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(AccessibilityID.Element.chapterCount(namespace))
                    Spacer()
                    TimestampView(current: $model.currentTime, total: model.info.duration)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(AccessibilityID.Element.timestamp(namespace))
                }
            }
            if let state = model.downloadState {
                DownloadRingView(state: state) { model.toggleDownloadPause() }
                    .padding(.leading, SpaceConstants.sx8.value)
                    .accessibilityIdentifier(AccessibilityID.Element.downloadRing(namespace))
            }
            PlayButtonView(isPlaying: $model.isPlaying) {
                model.play()
            } onPause: {
                model.pause()
            }
            .frame(height: SpaceConstants.sx24.value)
            .padding(.leading, SpaceConstants.sx8.value)
            .accessibilityIdentifier(AccessibilityID.Element.play(namespace))
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
            )
        )
        .backgroundColor(ColorConstants.background.value)
    }
}
