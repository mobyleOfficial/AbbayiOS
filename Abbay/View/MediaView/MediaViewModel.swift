//
//  MediaViewModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import Combine
import Foundation

final class MediaViewModel: ObservableObject {
    // MARK: - Properties
    private let playerObserver: PlayerObserverProtocol
    private(set) var info: AudioModel
    private let downloads: BookDownloadManagerProtocol?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Observed properties
    @Published
    var currentTime: Double = 0
    @Published
    var isPlaying: Bool = false
    @Published
    var currentChapter: Int = 0
    /// Non-nil only for a LibriVox book whose download is still incomplete.
    @Published
    private(set) var downloadState: BookDownloadState?

    // MARK: - Init
    /// `downloads` is resolved from the container only for LibriVox books, so imported rows never
    /// need it.
    init(
        _ model: AudioModel,
        playerObserver: PlayerObserverProtocol = PlayerObserver(DependencyContainer.shared.player),
        downloads: BookDownloadManagerProtocol? = nil
    ) {
        self.info = model
        self.downloads = model.librivoxID == nil ? nil : (downloads ?? DependencyContainer.shared.downloads)
        self.playerObserver = playerObserver
        self.currentTime = info.currentTime
        self.currentChapter = info.currentChapter(for: currentTime)
        observeDownloads()

        defer {
            // A row can be created after its book was already loaded: the library list is rebuilt
            // when search closes, and playback can start from Siri, CarPlay or another screen. It
            // never sees that play event, so pick up the current state here, as PlayerViewModel does.
            if let url = info.url, playerObserver.player.url == url {
                isPlaying = playerObserver.player.isPlaying(url)
                setupObserver()
            }
            self.playerObserver.subscribeToPlayUrlPublisher { [weak self, oldUrl = self.info.url] newInfo in
                guard let self = self else { return }
                if newInfo.url == oldUrl {
                    self.setupObserver()
                } else {
                    self.removeObserver()
                    self.isPlaying = false
                }
            }
        }
    }

    // MARK: - Methods
    func play() {
        playerObserver.player.play(&info)
    }

    func pause() {
        playerObserver.player.pause()
    }

    /// Pauses a running download, or resumes a paused one.
    func toggleDownloadPause() {
        guard let id = info.librivoxID, let state = downloadState else { return }
        if state.isPaused {
            downloads?.resume(bookID: id)
        } else {
            downloads?.pause(bookID: id)
        }
    }

    // MARK: - Helpers
    private func observeDownloads() {
        guard let id = info.librivoxID, let downloads else { return }
        // The manager emits on the main thread.
        downloads.statesPublisher
            .map { states -> BookDownloadState? in
                guard let state = states[id], !state.isComplete else { return nil }
                return state
            }
            .removeDuplicates()
            .sink { [weak self] in self?.downloadState = $0 }
            .store(in: &cancellables)
    }

    private func setupObserver() {
        playerObserver.subscribeToTimePublisher { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            self.isPlaying = self.playerObserver.player.isPlaying(self.info.url)
            self.currentChapter = self.info.currentChapter(for: self.currentTime)
        }
    }

    private func removeObserver() {
        playerObserver.cancelTimeSubscription()
    }
}
