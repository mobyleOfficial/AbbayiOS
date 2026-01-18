//
//  PlayerViewModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 10/07/23.
//

import Combine
import Foundation

final class PlayerViewModel: ObservableObject {
    // MARK: - Properties
    private(set) var info: AudioModel
    private let playerObserver: PlayerObserverProtocol

    // MARK: - Observed properties
    @Published
    var currentTime: Double = 0
    @Published
    var isPlaying: Bool = false
    @Published
    var currentChapter: Int = 0

    // MARK: - Init
    init(
        _ model: AudioModel,
        playerObserver: PlayerObserverProtocol = PlayerObserver(DependencyContainer.shared.player)
    ) {
        self.info = model
        self.playerObserver = playerObserver
        self.currentTime = info.currentTime
        setCurrentChapter(for: info.currentTime)

        defer {
            if playerObserver.player.url == model.url {
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

    func forward(withSeconds seconds: Double) {
        playerObserver.player.forward(withSeconds: seconds)
    }

    func backward(withSeconds seconds: Double) {
        playerObserver.player.backward(withSeconds: seconds)
    }

    func willSeek() {
        removeObserver()
    }

    func seek(_ seconds: Double) {
        setupObserver()
        playerObserver.player.seek(seconds)
    }

    func setCurrentChapter(for time: Double) {
        currentChapter = info.currentChapter(for: currentTime)
    }

    // MARK: - Setups
    private func setupObserver() {
        playerObserver.subscribeToTimePublisher { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            self.isPlaying = self.playerObserver.player.isPlaying(self.info.url)
        }
    }

    private func removeObserver() {
        playerObserver.cancelTimeSubscription()
    }
}
