//
//  Player.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 24/06/23.
//

import AVFoundation
import UIKit

protocol PlayerProtocol {
    typealias Observer = (CMTime) -> Void
    typealias ObserverId = UUID

    var url: URL? { get }

    func play(_ url: URL?)
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
    static let cacheKey = "timestamps"
    private let timeCache = Cache<URL, Double>.load(withName: Player.cacheKey)
    private let player = AVPlayer()
    private var observers = [ObserverId: Any]()
    private var stateObserver: NSObjectProtocol?

    var url: URL?

    // MARK: - Init
    init() {
        defer {
            stateObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.saveTime(for: self?.url)
            }
        }
    }

    // MARK: - Deinit
    deinit {
        saveTime(for: self.url)
        removeObservers()
    }

    // MARK: - PlayerProtocol
    func play(_ url: URL?) {
        guard let url = url else { return }
        if url != self.url {
            saveTime(for: self.url)
            updatePlayItem(with: url)
            seek(timeCache[url] ?? .zero)
        }
        player.play()
    }

    func pause() {
        saveTime(for: url)
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

    private func updatePlayItem(with url: URL) {
        let isSecure = url.startAccessingSecurityScopedResource()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        self.url = url
        if isSecure { url.stopAccessingSecurityScopedResource() }
    }

    private func saveTime(for url: URL? = nil) {
        let currentTime = player.currentTime().seconds
        if let url = url, !currentTime.isNaN {
            timeCache[url] = currentTime
        }
        try? timeCache.save(withName: Player.cacheKey)
    }
}
