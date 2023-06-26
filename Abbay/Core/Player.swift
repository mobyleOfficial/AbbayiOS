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
    func addObserver(interval seconds: Double, observer: @escaping Observer)
    func isPlaying(_ url: URL?) -> Bool
}

final class Player: PlayerProtocol {
    private let timeCache = Cache<URL, Double>()
    private let player = AVPlayer()
    private var observers = [Observer]()

    var url: URL?

    deinit {
        for observer in observers {
            player.removeTimeObserver(observer)
        }
    }

    func play(_ url: URL?) {
        guard let url = url else { return }
        if url != self.url {
            if let url = self.url {
                timeCache[url] = player.currentTime().seconds
            }
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            let time = CMTime(seconds: timeCache[url] ?? .zero, preferredTimescale: 1)
            seek(time)
            self.url = url
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
        let newTime = CMTime(seconds: newSeconds, preferredTimescale: 1)
        seek(newTime)
    }

    func backward(withSeconds seconds: Double) {
        let currentSeconds = player.currentTime().seconds
        let newSeconds = currentSeconds.advanced(by: -seconds)
        let newTime = CMTime(seconds: newSeconds, preferredTimescale: 1)
        seek(newTime)
    }

    func addObserver(interval seconds: Double, observer: @escaping Observer) {
        let second = CMTime(seconds: seconds, preferredTimescale: 1)
        player.addPeriodicTimeObserver(forInterval: second, queue: .main, using: observer)
        observers.append(observer)
    }

    func isPlaying(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        return self.url == url && player.timeControlStatus == .playing
    }

    private func seek(_ time: CMTime) {
        player.seek(to: time)
    }
}
