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
    private let onSelection: MediaSelection
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
        onSelection: MediaSelection
    ) {
        self.info = model
        self.player = player
        self.onSelection = onSelection
        self.currentTime = info.currentTime

        defer {
            self.onSelection.subscribe { [weak self] selectedInfo in
                guard let self = self else { return }
                if selectedInfo?.url == self.info.url {
                    self.observer = self.player.addObserver(interval: 1) { time in
                        self.currentTime = time.seconds
                        self.isPlaying = self.player.isPlaying(self.info.url)
                    }
                } else {
                    self.removeObserver()
                    self.isPlaying = false
                }
            }
        }
    }

    // MARK: - deinit
    deinit {
        removeObserver()
    }

    // MARK: - Methods
    func play() {
        player.play(info.url)
        onSelection.select(info)
    }

    func pause() {
        player.pause()
    }

    // MARK: - Helpers
    private func removeObserver() {
        player.removeObserver(observer)
        observer = nil
    }
}
