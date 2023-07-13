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
    private var observer: PlayerProtocol.ObserverId?
    private(set) var info: AudioModel

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
            addObserver()
        }
    }

    // MARK: - deinit
    deinit {
        removeObserver()
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
        addObserver()
    }

    func setCurrentChapter(for time: Double) {
        currentChapter = info.currentChapter(for: currentTime) + 1
    }

    // MARK: - Helpers
    private func addObserver() {
        observer = player.addObserver(interval: 1) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            self.isPlaying = self.player.isPlaying(self.info.url)
        }
    }

    private func removeObserver() {
        player.removeObserver(observer)
        observer = nil
    }
}
