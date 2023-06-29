//
//  Player.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 24/06/23.
//

import AVFoundation

protocol PlayerProtocol {
    typealias Observer = (CMTime) -> Void

    func play(_ url: URL?)
    func pause()
    func forward(withSeconds seconds: Double)
    func backward(withSeconds seconds: Double)
    func addObserver(interval seconds: Double, url: URL?, observer: @escaping Observer)
    func removeObservers(for url: URL?)
    func removeObservers()
    func isPlaying(_ url: URL?) -> Bool
}

final class Player: PlayerProtocol {
    // MARK: - Properties
    private let timeCache = Cache<URL, Double>()
    private let player = AVPlayer()
    private var observers = [URL: [Any]]()

    var url: URL?

    // MARK: - Deinit
    deinit {
        removeObservers()
    }

    // MARK: - PlayerProtocol
    func play(_ url: URL?) {
        guard let url = url else { return }
        if url != self.url {
            if let url = self.url {
                timeCache[url] = player.currentTime().seconds
            }
            updatePlayItem(with: url)
            seek(timeCache[url] ?? .zero)
        }
        player.play()
    }

    func pause() {
        if let url = url {
            timeCache[url] = player.currentTime().seconds
        }
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

    func addObserver(interval seconds: Double, url: URL?, observer: @escaping Observer) {
        let second = CMTime(seconds: seconds, preferredTimescale: 1)
        let observer = player.addPeriodicTimeObserver(forInterval: second, queue: .main, using: observer)
        if let url = url {
            var currentObservers = observers[url] ?? []
            currentObservers.append(observer)
            observers[url] = currentObservers
        }
    }

    func removeObservers(for url: URL?) {
        guard let url = url else { return }
        observers.removeValue(forKey: url)?.forEach { observer in
            player.removeTimeObserver(observer)
        }
    }

    func removeObservers() {
        for url in observers.keys {
            removeObservers(for: url)
        }
        observers.removeAll()
    }

    func isPlaying(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        return self.url == url && player.timeControlStatus == .playing
    }

    // MARK: - Helpers
    private func seek(_ seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 1)
        seek(time)
    }

    private func seek(_ time: CMTime) {
        player.seek(to: time)
    }

    private func updatePlayItem(with url: URL) {
        let isSecure = url.startAccessingSecurityScopedResource()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        self.url = url
        if isSecure { url.stopAccessingSecurityScopedResource() }
    }
}
