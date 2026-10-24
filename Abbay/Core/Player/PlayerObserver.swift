//
//  PlayerObserver.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 30/11/25.
//

import AVFoundation
import Combine

/// A per-consumer subscription to the player's publishers. Its one remaining consumer is
/// `CarPlaySceneDelegate` (CarPlay was out of scope for the tabs + mini player work): every other
/// view and view model reads `PlaybackCenter`'s `PlaybackState` and `PlaybackClock`; the center
/// subscribes once per publisher (see `SubscriptionBudgetTests`). Don't add new users;
/// move CarPlay onto `PlaybackCenter` and delete this when CarPlay is next touched.
protocol PlayerObserverProtocol {
    var player: PlayerProtocol { get }

    func subscribeToTimePublisher(subscription: @escaping (CMTime) -> Void)
    func subscribeToPlayUrlPublisher(subscription: @escaping (AudioModel) -> Void)
    func cancelTimeSubscription()
    func cancelUrlSubscription()
}

final class PlayerObserver: PlayerObserverProtocol {
    // MARK: - Properties
    let player: PlayerProtocol
    private var timeCancellables = Set<AnyCancellable>()
    private var urlCancellables = Set<AnyCancellable>()

    // MARK: Init
    init(_ player: PlayerProtocol) {
        self.player = player
    }
}

// MARK: - Protocol Methods
extension PlayerObserver {
    func subscribeToTimePublisher(subscription: @escaping (CMTime) -> Void) {
        guard timeCancellables.isEmpty else { return }
        player.currentTimePublisher
            .sink(receiveValue: subscription)
            .store(in: &timeCancellables)
    }

    func subscribeToPlayUrlPublisher(subscription: @escaping (AudioModel) -> Void) {
        // Guarded like the time path. `CarPlaySceneDelegate.setupObservers` runs on every
        // `didConnect`, so without this a reconnect stacks a second closure and `currentAudio`
        // is written twice per publish (#94).
        guard urlCancellables.isEmpty else { return }
        player.playUrlSubjectPublisher
            .sink(receiveValue: subscription)
            .store(in: &urlCancellables)
    }

    func cancelTimeSubscription() {
        timeCancellables.removeAll()
    }

    /// Counterpart to `cancelTimeSubscription`, so a teardown can release both halves of what
    /// `setupObservers` registered rather than only the time half (#94).
    func cancelUrlSubscription() {
        urlCancellables.removeAll()
    }
}
