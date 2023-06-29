//
//  FloatingPlayerModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import Foundation

final class FloatingPlayerViewModel: ObservableObject {
    // MARK: - Properties
    private let player: PlayerProtocol
    let info: AudioModel

    // MARK: - Observed properties
    @Published
    var currentTime: Double = 0
    @Published
    var isPlaying: Bool = false

    // MARK: - Init
    init(_ model: AudioModel, player: PlayerProtocol) {
        self.info = model
        self.player = player

        defer {
            player.addObserver(interval: 1, url: info.url) { [weak self] time in
                guard let self = self else { return }
                self.currentTime = time.seconds
                self.isPlaying = self.player.isPlaying(self.info.url)
            }
        }
    }

    // MARK: - Methods
    func play() {
        player.play(info.url)
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
}
