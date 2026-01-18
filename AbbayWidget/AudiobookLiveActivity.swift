//
//  AudiobookLiveActivity.swift
//  AbbayWidget
//
//  Created for Live Activity support
//

import ActivityKit
import WidgetKit
import SwiftUI

struct AudiobookLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AudiobookActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here
                DynamicIslandExpandedRegion(.leading) {
                    if let imageData = context.attributes.imageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                    } else {
                        Image(systemName: "book.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                            .foregroundColor(.gray)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(formatTime(context.state.currentTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatTime(context.attributes.duration))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.attributes.author)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        HStack(spacing: 12) {
                            Link(destination: URL(string: "abbay://skip-backward")!) {
                                Image(systemName: "gobackward.15")
                                    .font(.system(size: 20))
                            }

                            Link(destination: URL(string: "abbay://play-pause")!) {
                                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 24))
                            }

                            Link(destination: URL(string: "abbay://skip-forward")!) {
                                Image(systemName: "goforward.15")
                                    .font(.system(size: 20))
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        ProgressView(value: context.state.currentTime, total: context.attributes.duration)
                            .tint(.blue)

                        HStack {
                            Text("Chapter \(context.attributes.currentChapter + 1) of \(context.attributes.totalChapters)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
            } compactLeading: {
                if let imageData = context.attributes.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "book.fill")
                        .foregroundColor(.gray)
                }
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundColor(.blue)
            } minimal: {
                Image(systemName: context.state.isPlaying ? "play.fill" : "pause.fill")
                    .foregroundColor(.blue)
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<AudiobookActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            // Cover art
            if let imageData = context.attributes.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
            } else {
                Image(systemName: "book.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .foregroundColor(.gray)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Title and author
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.attributes.author)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Progress bar with time
                VStack(spacing: 4) {
                    ProgressView(value: context.state.currentTime, total: context.attributes.duration)
                        .tint(.blue)

                    HStack {
                        Text(formatTime(context.state.currentTime))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Chapter \(context.attributes.currentChapter + 1) of \(context.attributes.totalChapters)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatTime(context.attributes.duration))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Playback controls
                HStack(spacing: 16) {
                    Spacer()

                    Link(destination: URL(string: "abbay://skip-backward")!) {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 20))
                    }

                    Link(destination: URL(string: "abbay://play-pause")!) {
                        Image(systemName: context.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32))
                    }

                    Link(destination: URL(string: "abbay://skip-forward")!) {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 20))
                    }

                    Spacer()
                }
            }
        }
        .padding(12)
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}
