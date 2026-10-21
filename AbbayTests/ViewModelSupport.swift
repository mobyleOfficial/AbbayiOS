//
//  ViewModelSupport.swift
//  AbbayTests
//

@testable import Abbay
import Foundation

/// Shared sample models for the view-model suites. Chapters are contiguous at 0-100, 100-200
/// and 200-400 so chapter-index assertions read clearly.
enum ViewModelSupport {
    static let url = URL(string: "file:///vm/chaptered.m4b")

    static func chaptered(currentTime: Double = 0) -> AudioModel {
        AudioModel(
            title: "Chaptered",
            albumName: "Album",
            artist: "Artist",
            duration: 400,
            currentTime: currentTime,
            chapters: [
                ChapterModel(title: "one", startTime: 0, duration: 100),
                ChapterModel(title: "two", startTime: 100, duration: 100),
                ChapterModel(title: "three", startTime: 200, duration: 200)
            ],
            url: url
        )
    }

    /// An observer whose player already reports `url` as loaded and playing.
    static func observer(loaded model: AudioModel, isPlaying: Bool = true) -> MockPlayerObserver {
        let player = MockPlayer()
        player.url = model.url
        player.isPlayingResult = isPlaying
        let observer = MockPlayerObserver()
        observer.player = player
        return observer
    }
}
