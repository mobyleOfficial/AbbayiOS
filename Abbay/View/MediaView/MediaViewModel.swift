//
//  MediaViewModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import Foundation

/// A library row's actions, and nothing else: it holds no player subscriptions and no state. What
/// the row shows comes from `PlaybackState` and its book's `BookDownloadEntry` (see
/// `MediaView.DetailModel`), so it is cheap to build one per action.
@MainActor
struct MediaViewModel {
    private let book: AudioModel
    private let player: PlayerProtocol?
    private let downloads: DownloadStateStore?

    init(_ book: AudioModel, player: PlayerProtocol?, downloads: DownloadStateStore?) {
        self.book = book
        self.player = player
        self.downloads = downloads
    }

    func play() {
        // `play` may fill in the bookmark; the saved copy is updated by the player itself.
        var book = book
        player?.play(&book)
    }

    func pause() {
        player?.pause()
    }

    /// Pauses a running download, or resumes a paused one. Imported books have no download.
    func toggleDownload() {
        guard let id = book.librivoxID, let downloads, let state = downloads.entry(for: id).state else { return }
        if state.isPaused {
            downloads.resume(bookID: id)
        } else {
            downloads.pause(bookID: id)
        }
    }
}
