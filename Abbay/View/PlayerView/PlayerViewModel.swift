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
    private let player: PlayerProtocol
    private(set) var info: AudioModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Observed properties
    @Published
    var currentTime: Double = 0
    @Published
    var isPlaying: Bool = false
    @Published
    var currentChapter: Int = 0

    // MARK: - Init
    init(_ model: AudioModel, player: PlayerProtocol) {
        self.info = model
        self.player = player
        self.currentTime = info.currentTime
        setCurrentChapter(for: info.currentTime)

        defer {
            if player.url == model.url {
                setupObserver()
            }
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
        setupObserver()
        player.seek(seconds)
    }

    func setCurrentChapter(for time: Double) {
        currentChapter = info.currentChapter(for: currentTime)
    }

    // MARK: - Setups
    private func setupObserver() {
        player.currentTimePublisher
            .sink { [weak self] time in
                guard let self = self else { return }
                self.currentTime = time.seconds
                self.isPlaying = self.player.isPlaying(self.info.url)
            }
            .store(in: &cancellables)
    }

    private func removeObserver() {
        cancellables.removeAll()
    }
}
