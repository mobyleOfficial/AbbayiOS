//
//  MediaViewModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import Combine
import Foundation

final class MediaViewModel: ObservableObject {
    // MARK: - Properties
    private let player: PlayerProtocol
    private let onSelection: MediaSelection
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
    init(
        _ model: AudioModel,
        player: PlayerProtocol,
        onSelection: MediaSelection
    ) {
        self.info = model
        self.player = player
        self.onSelection = onSelection
        self.currentTime = info.currentTime
        self.currentChapter = info.currentChapter(for: currentTime)

        defer {
            self.onSelection.subscribe { [weak self] selectedInfo in
                guard let self = self else { return }
                if selectedInfo?.url == self.info.url {
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
        player.play(&info)
        onSelection.select(info)
    }

    func pause() {
        player.pause()
    }

    // MARK: - Helpers
    private func setupObserver() {
        player.currentTimePublisher
            .sink { [weak self] time in
                guard let self = self else { return }
                self.currentTime = time.seconds
                self.isPlaying = self.player.isPlaying(self.info.url)
                self.currentChapter = self.info.currentChapter(for: self.currentTime) + 1
            }
            .store(in: &cancellables)
    }

    private func removeObserver() {
        cancellables.removeAll()
    }
}
