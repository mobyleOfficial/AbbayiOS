//
//  MockFileLoader.swift
//  AbbayTests
//

@testable import Abbay
import AVFoundation
import Foundation

final class MockFileLoader: FileLoaderProtocol {
    var modelsToReturn: [AudioModel] = []
    var loadURLsCallCount = 0

    func load(url: URL) async -> AudioModel? { modelsToReturn.first }
    func load(urls: [URL]) async -> [AudioModel] {
        loadURLsCallCount += 1
        return modelsToReturn
    }
}

final class MockDeleteAudioUseCase: DeleteAudioUseCaseProtocol {
    var deletedAudios: [AudioModel] = []

    func execute(_ audio: AudioModel) {
        deletedAudios.append(audio)
    }
}

final class MockPlayerObserver: PlayerObserverProtocol {
    var player: PlayerProtocol = MockPlayer()

    private(set) var timeSubscriptions: [(CMTime) -> Void] = []
    private(set) var urlSubscriptions: [(AudioModel) -> Void] = []
    private(set) var cancelTimeCallCount = 0

    func subscribeToTimePublisher(subscription: @escaping (CMTime) -> Void) {
        timeSubscriptions.append(subscription)
    }

    func subscribeToPlayUrlPublisher(subscription: @escaping (AudioModel) -> Void) {
        urlSubscriptions.append(subscription)
    }

    func cancelTimeSubscription() {
        cancelTimeCallCount += 1
        timeSubscriptions.removeAll()
    }

    // MARK: - Test drivers

    /// Fires every live time subscription, as the real player's periodic observer would.
    func emitTime(_ seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        for subscription in timeSubscriptions {
            subscription(time)
        }
    }

    /// Fires every URL subscription, as `Player.updatePlayItem` would on a new item.
    func emitPlayUrl(_ model: AudioModel) {
        for subscription in urlSubscriptions {
            subscription(model)
        }
    }
}
