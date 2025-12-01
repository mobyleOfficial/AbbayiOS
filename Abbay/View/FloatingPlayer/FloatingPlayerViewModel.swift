//
//  FloatingPlayerModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import Combine
import Foundation

final class FloatingPlayerViewModel: ObservableObject {
    // MARK: - Properties
    private let player: PlayerProtocol
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
        player: PlayerProtocol,
        playerObserver: PlayerObserverProtocol? = nil
    ) {
        self.info = model
        self.player = player
        self.playerObserver = playerObserver ?? PlayerObserver(player)
        self.currentTime = info.currentTime
        setCurrentChapter(for: info.currentTime)

        defer {
            setupObserver()
        }
    }

    // MARK: - Methods
    func play() {
        player.play(&info)
    }

    func pause() {
        player.pause()
    }

    func forward(withSeconds seconds: Double) {
        player.forward(withSeconds: seconds)
    }

    func backward(withSeconds seconds: Double) {
        player.backward(withSeconds: seconds)
    }

    func willSeek() {
        removeObserver()
    }

    func seek(_ seconds: Double) {
        player.seek(seconds)
        setupObserver()
    }

    func setCurrentChapter(for time: Double) {
        currentChapter = info.currentChapter(for: currentTime) + 1
    }

    // MARK: - Helpers
    private func setupObserver() {
        playerObserver.subscribeToTimePublisher { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            self.isPlaying = self.player.isPlaying(self.info.url)
        }
    }

    private func removeObserver() {
        playerObserver.cancelTimeSubscription()
    }
}
