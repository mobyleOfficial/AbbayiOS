//
//  Player.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 24/06/23.
//

import AVFoundation
import Combine
import UIKit

protocol PlayerProtocol {
    var url: URL? { get }
    var currentTime: Double { get }
    var currentTimePublisher: AnyPublisher<CMTime, Never> { get }
    var playUrlSubjectPublisher: AnyPublisher<AudioModel, Never> { get }

    func play(_ model: inout AudioModel)
    func pause()
    func forward(withSeconds seconds: Double)
    func backward(withSeconds seconds: Double)
    func isPlaying(_ url: URL?) -> Bool
    func seek(_ seconds: Double)
    func cleanup()
    func skipToNextChapter()
    func skipToPreviousChapter()
}

final class Player: PlayerProtocol {
    // MARK: - Properties
    private let player = AVPlayer()
    private var model: AudioModel?
    private let saveAudioUseCase: SaveAudioUseCaseProtocol
    private let intentDonor: IntentDonorProtocol
    private let librarySnapshotWriter: LibrarySnapshotWriterProtocol
    private let audioSessionActivator: AudioSessionActivatorProtocol
    private let bookmarkProvider: BookmarkProviderProtocol
    private var cancellables = Set<AnyCancellable>()
    private var hasSecurityAccess = false
    private let currentTimeSubject = PassthroughSubject<CMTime, Never>()
    private let playUrlSubject = PassthroughSubject<AudioModel, Never>()
    private var timeObserverToken: Any?

    var url: URL? {
        model?.url
    }

    var currentTimePublisher: AnyPublisher<CMTime, Never> {
        currentTimeSubject.eraseToAnyPublisher()
    }

    var playUrlSubjectPublisher: AnyPublisher<AudioModel, Never> {
        playUrlSubject.eraseToAnyPublisher()
    }

    var currentTime: Double {
        player.currentTime().seconds
    }

    // MARK: - Init
    init(
        saveAudioUseCase: SaveAudioUseCaseProtocol = SaveAudioUseCase(
            repository: LoadAudioRepository()
        ),
        intentDonor: IntentDonorProtocol = IntentDonor.shared,
        librarySnapshotWriter: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter.shared,
        audioSessionActivator: AudioSessionActivatorProtocol = AudioSessionActivator(),
        bookmarkProvider: BookmarkProviderProtocol = BookmarkProvider()
    ) {
        self.saveAudioUseCase = saveAudioUseCase
        self.intentDonor = intentDonor
        self.librarySnapshotWriter = librarySnapshotWriter
        self.audioSessionActivator = audioSessionActivator
        self.bookmarkProvider = bookmarkProvider
        setupTimeObserver()

        // Initialize Now Playing and set player reference
        NowPlayingManager.shared.setPlayer(self, currentAudio: nil)
    }

    // MARK: - Deinit
    deinit {
        cleanup()
    }

    // MARK: - Cleanup
    func cleanup() {
        saveTime()
        stopAccessingCurrentURL()
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
        NowPlayingManager.shared.clearNowPlaying()
    }

    // MARK: - PlayerProtocol
    func play(_ model: inout AudioModel) {
        // TODO: Add logging for playback attempts using logging library
        guard let url = model.url else {
            print("⚠️ Player.play: URL is nil")
            return
        }
        print("▶️ Player.play: Attempting to play \(url.lastPathComponent)")
        if url != self.url {
            saveTime()
            updatePlayItem(model)
            seek(model.currentTime)
        }
        player.play()
        print("▶️ Player.play: player.play() called, status: \(player.timeControlStatus.rawValue)")
    }

    func pause() {
        saveTime()
        player.pause()
    }

    func forward(withSeconds seconds: Double) {
        let currentSeconds = player.currentTime().seconds
        let newSeconds = currentSeconds.advanced(by: seconds)
        seek(newSeconds)
    }

    func backward(withSeconds seconds: Double) {
        let currentSeconds = player.currentTime().seconds
        let newSeconds = currentSeconds.advanced(by: -seconds)
        seek(newSeconds)
    }


    func isPlaying(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        return self.url == url && player.timeControlStatus == .playing
    }

    func seek(_ seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 1)
        seek(time)
    }

    func skipToNextChapter() {
        guard let model = model else { return }
        let currentChapterIndex = model.currentChapter(for: currentTime)
        let nextChapterIndex = currentChapterIndex + 1
        guard nextChapterIndex < model.chapters.count else { return }
        seek(model.chapters[nextChapterIndex].startTime)
    }

    func skipToPreviousChapter() {
        guard let model = model else { return }
        let currentChapterIndex = model.currentChapter(for: currentTime)
        let currentChapter = model.chapters[currentChapterIndex]

        // If more than 15 seconds into the chapter, go to start of current chapter
        // Otherwise, go to previous chapter
        if currentTime - currentChapter.startTime > 15 {
            seek(currentChapter.startTime)
        } else if currentChapterIndex > 0 {
            seek(model.chapters[currentChapterIndex - 1].startTime)
        } else {
            seek(0)
        }
    }

    // MARK: - Helpers
    private func seek(_ time: CMTime) {
        player.seek(to: time)
    }

    private func updatePlayItem(_ item: AudioModel) {
        // TODO: Add logging for player item updates using logging library
        guard let url = item.url else {
            print("⚠️ updatePlayItem: URL is nil")
            return
        }

        cancellables.removeAll()

        stopAccessingCurrentURL()

        hasSecurityAccess = url.startAccessingSecurityScopedResource()
        print("🔐 updatePlayItem: Security scoped access: \(hasSecurityAccess) for \(url.lastPathComponent)")
        model = item
        LastPlayedStore.save(url: url)

        // Update NowPlayingManager with current audio
        NowPlayingManager.shared.setPlayer(self, currentAudio: item)

        let playerItem = AVPlayerItem(url: url)

        // TODO: Add logging for player item failures using logging library
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { notification in
            // TODO: Log AVPlayerItem failure
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                print("❌ AVPlayerItem failed: \(error.localizedDescription)")
            }
        }

        // TODO: Add logging for player item status changes using logging library
        playerItem.publisher(for: \.status)
            .sink { status in
                // TODO: Log status changes (readyToPlay, failed, unknown)
                switch status {
                case .readyToPlay:
                    print("✅ AVPlayerItem ready to play")
                case .failed:
                    if let error = playerItem.error {
                        print("❌ AVPlayerItem failed with error: \(error.localizedDescription)")
                    }
                case .unknown:
                    print("⚠️ AVPlayerItem status unknown")
                @unknown default:
                    print("⚠️ AVPlayerItem unknown status")
                }
            }
            .store(in: &cancellables)

        player.replaceCurrentItem(with: playerItem)
        playUrlSubject.send(item)
    }

    private func stopAccessingCurrentURL() {
        // TODO: Add logging for security scope access using logging library
        if hasSecurityAccess, let url = url {
            url.stopAccessingSecurityScopedResource()
            print("🔒 Stopped accessing: \(url.lastPathComponent)")
            hasSecurityAccess = false
        }
    }

    private func saveTime() {
        let currentTime = player.currentTime().seconds
        if !currentTime.isNaN, var model = model {
            model.currentTime = currentTime
            try? saveAudioUseCase.execute(model)
        }
    }

    // MARK: - Setups
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            self?.currentTimeSubject.send(time)

            // Update Now Playing with current time
            guard let self = self, let model = self.model else { return }
            let currentTime = time.seconds
            let isPlaying = self.player.timeControlStatus == .playing

            NowPlayingManager.shared.updateNowPlaying(
                for: model,
                currentTime: currentTime,
                isPlaying: isPlaying
            )
        }
    }
}
