//
//  LiveActivityManager.swift
//  Abbay
//
//  Manages Live Activity lifecycle for audiobook playback
//

import ActivityKit
import Foundation
import UIKit

class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var currentActivity: Activity<AudiobookActivityAttributes>?

    private init() {}

    func startActivity(for audio: AudioModel, isPlaying: Bool) {
        // End any existing activity first
        endActivity()

        print("🔴 LiveActivity: Starting activity for \(audio.title)")
        print("🔴 LiveActivity: areActivitiesEnabled = \(ActivityAuthorizationInfo().areActivitiesEnabled)")

        // Compress image data to fit Live Activity size limits (4KB limit)
        let compressedImageData = compressImageData(audio.imageData)

        let attributes = AudiobookActivityAttributes(
            title: audio.title,
            author: audio.artist.isEmpty ? audio.albumName : audio.artist,
            duration: audio.duration,
            imageData: compressedImageData,
            currentChapter: audio.currentChapter(for: audio.currentTime),
            totalChapters: max(audio.chapters.count, 1)
        )

        let contentState = AudiobookActivityAttributes.ContentState(
            currentTime: audio.currentTime,
            isPlaying: isPlaying
        )

        do {
            currentActivity = try Activity<AudiobookActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )
            print("🟢 LiveActivity: Successfully started - ID: \(currentActivity?.id ?? "unknown")")
        } catch {
            print("🔴 LiveActivity: Failed to start - \(error.localizedDescription)")
        }
    }

    func updateActivity(currentTime: Double, isPlaying: Bool, currentChapter: Int) {
        guard let activity = currentActivity else { return }

        let contentState = AudiobookActivityAttributes.ContentState(
            currentTime: currentTime,
            isPlaying: isPlaying
        )

        Task {
            await activity.update(
                .init(state: contentState, staleDate: nil)
            )
        }
    }

    func updatePlayingState(isPlaying: Bool) {
        guard let activity = currentActivity else { return }

        let contentState = AudiobookActivityAttributes.ContentState(
            currentTime: activity.content.state.currentTime,
            isPlaying: isPlaying
        )

        Task {
            await activity.update(
                .init(state: contentState, staleDate: nil)
            )
        }
    }

    func endActivity() {
        guard let activity = currentActivity else { return }

        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            currentActivity = nil
        }
    }

    var isActivityActive: Bool {
        currentActivity != nil
    }

    // MARK: - Helper Methods
    private func compressImageData(_ imageData: Data?) -> Data? {
        guard let imageData = imageData,
              let image = UIImage(data: imageData) else {
            return nil
        }

        // Live Activities have a 4KB limit, so we need to compress aggressively
        // Start with a small size (60x60) for the thumbnail
        let targetSize = CGSize(width: 60, height: 60)

        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: targetSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let resized = resizedImage else { return nil }

        // Try compression at different quality levels until under 4KB
        var compressionQuality: CGFloat = 0.5
        var compressedData = resized.jpegData(compressionQuality: compressionQuality)

        while let data = compressedData, data.count > 4096, compressionQuality > 0.1 {
            compressionQuality -= 0.1
            compressedData = resized.jpegData(compressionQuality: compressionQuality)
        }

        if let data = compressedData, data.count <= 4096 {
            print("🔴 LiveActivity: Compressed image from \(imageData.count) to \(data.count) bytes")
            return data
        }

        print("🔴 LiveActivity: Could not compress image below 4KB, using nil")
        return nil
    }
}
