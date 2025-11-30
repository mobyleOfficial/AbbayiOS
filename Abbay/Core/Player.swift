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
    typealias Observer = (CMTime) -> Void
    typealias ObserverId = UUID

    var url: URL? { get }

    func play(_ model: inout AudioModel)
    func pause()
    func forward(withSeconds seconds: Double)
    func backward(withSeconds seconds: Double)
    func addObserver(interval seconds: Double, observer: @escaping Observer) -> ObserverId
    func removeObserver(_ id: ObserverId?)
    func removeObservers()
    func isPlaying(_ url: URL?) -> Bool
    func seek(_ seconds: Double)
}

final class Player: PlayerProtocol {
    // MARK: - Properties
    private let player = AVPlayer()
    private var observers = [ObserverId: Any]()
    private var stateObserver: NSObjectProtocol?
    private var model: AudioModel?
    private let saveAudioUseCase: SaveAudioUseCaseProtocol
    private var cancellables = Set<AnyCancellable>()
    private var hasSecurityAccess = false

    var url: URL? {
        model?.url
    }

    // MARK: - Init
    init(saveAudioUseCase: SaveAudioUseCaseProtocol = SaveAudioUseCase()) {
        self.saveAudioUseCase = saveAudioUseCase
        defer {
            stateObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.saveTime()
            }
        }
    }

    // MARK: - Deinit
    deinit {
        saveTime()
        stopAccessingCurrentURL()
        removeObservers()
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

    func addObserver(interval seconds: Double, observer: @escaping Observer) -> ObserverId {
        let id = UUID()
        let second = CMTime(seconds: seconds, preferredTimescale: 1)
        observers[id] = player.addPeriodicTimeObserver(forInterval: second, queue: .main, using: observer)
        return id
    }

    func removeObserver(_ id: ObserverId?) {
        guard let id = id,
        let observer = observers.removeValue(forKey: id)
        else { return }
        player.removeTimeObserver(observer)
    }

    func removeObservers() {
        for id in observers.keys {
            removeObserver(id)
        }
        guard let stateObserver = stateObserver else { return }
        NotificationCenter.default.removeObserver(stateObserver)
    }

    func isPlaying(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        return self.url == url && player.timeControlStatus == .playing
    }

    func seek(_ seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 1)
        seek(time)
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

        // Stop accessing previous URL before switching
        stopAccessingCurrentURL()

        // Start accessing new URL and update model
        hasSecurityAccess = url.startAccessingSecurityScopedResource()
        print("🔐 updatePlayItem: Security scoped access: \(hasSecurityAccess) for \(url.lastPathComponent)")
        model = item

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
    }

    private func stopAccessingCurrentURL() {
        // TODO: Add logging for security scope access using logging library
        // Only stop if we successfully started accessing
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
}
