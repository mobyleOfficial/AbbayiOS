//
//  PlayerObserver.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/25.
//

import AVFoundation
import Combine

protocol PlayerObserverProtocol {
    func subscribeToTimePublisher(subscription: @escaping (CMTime) -> Void)
    func subscribeToPlayUrlPublisher(subscription: @escaping (AudioModel) -> Void)
    func cancelTimeSubscription()
}

final class PlayerObserver {
    // MARK: - Properties
    private let player: PlayerProtocol
    private var timeCancellables = Set<AnyCancellable>()
    private var urlCancellables = Set<AnyCancellable>()

    // MARK: Init
    init(_ player: PlayerProtocol) {
        self.player = player
    }
}

// MARK: - PlayerObserverProtocol
extension PlayerObserver: PlayerObserverProtocol {
    func subscribeToTimePublisher(subscription: @escaping (CMTime) -> Void) {
        guard timeCancellables.isEmpty else { return }
        player.currentTimePublisher
            .sink(receiveValue: subscription)
            .store(in: &timeCancellables)
    }

    func subscribeToPlayUrlPublisher(subscription: @escaping (AudioModel) -> Void) {
        player.playUrlSubjectPublisher
            .sink(receiveValue: subscription)
            .store(in: &urlCancellables)
    }

    func cancelTimeSubscription() {
        timeCancellables.removeAll()
    }
}
