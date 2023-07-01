//
//  MediaViewModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import Foundation

final class MediaViewModel: ObservableObject {
    // MARK: - Properties
    private let player: PlayerProtocol
    private let onSelect: (AudioModel) -> Void
    private var observer: PlayerProtocol.ObserverId?
    let info: AudioModel

    // MARK: - Observed properties
    @Published
    var currentTime: Double = 0
    @Published
    var isPlaying: Bool = false

    // MARK: - Init
    init(
        _ model: AudioModel,
        player: PlayerProtocol,
        onSelect: @escaping (AudioModel) -> Void
    ) {
        self.info = model
        self.player = player
        self.onSelect = onSelect

        defer {
            if player.url == info.url {
                observer = player.addObserver(interval: 1) { [weak self] time in
                    guard let self = self else { return }
                    self.currentTime = time.seconds
                    self.isPlaying = self.player.isPlaying(self.info.url)
                }
            }
        }
    }

    // MARK: - deinit
    deinit {
        player.removeObserver(observer)
    }

    // MARK: - Methods
    func play() {
        player.play(info.url)
        onSelect(info)
    }

    func pause() {
        player.pause()
    }
}
