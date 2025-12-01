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
    func cancelTimeSubscription()
}

final class PlayerObserver {
    // MARK: - Properties
    private let player: PlayerProtocol
    private var timeCancellables = Set<AnyCancellable>()

    // MARK: Init
    init(_ player: PlayerProtocol) {
        self.player = player
    }
}

// MARK: - PlayerObserverProtocol
extension PlayerObserver: PlayerObserverProtocol {
    func subscribeToTimePublisher(subscription: @escaping (CMTime) -> Void) {
        player.currentTimePublisher
            .sink(receiveValue: subscription)
            .store(in: &timeCancellables)
    }

    func cancelTimeSubscription() {
        timeCancellables.removeAll()
    }
}
