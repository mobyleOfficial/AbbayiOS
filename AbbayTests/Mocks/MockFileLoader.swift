//
//  MockFileLoader.swift
//  AbbayTests
//

@testable import Abbay
import AVFoundation
import Foundation

final class MockFileLoader: FileLoaderProtocol {
    var modelsToReturn: [AudioModel] = []
    /// What `load(urls:)` reports as failed, alongside `modelsToReturn`.
    var failedURLsToReturn: [URL] = []
    var loadURLsCallCount = 0
    private(set) var loadedURLs: [[URL]] = []

    func load(url: URL) async -> AudioModel? { modelsToReturn.first }
    func load(urls: [URL]) async -> FileImportResult {
        loadURLsCallCount += 1
        loadedURLs.append(urls)
        return FileImportResult(loaded: modelsToReturn, failed: failedURLsToReturn)
    }
}

final class MockDeleteAudioUseCase: DeleteAudioUseCaseProtocol {
    /// Every call, as passed (an empty one too).
    private(set) var batches: [[AudioModel]] = []
    var deletedAudios: [AudioModel] { batches.flatMap { $0 } }

    func execute(_ audios: [AudioModel]) {
        batches.append(audios)
    }
}

final class MockPlayerObserver: PlayerObserverProtocol {
    var player: PlayerProtocol = MockPlayer()

    private(set) var timeSubscriptions: [(CMTime) -> Void] = []
    private(set) var urlSubscriptions: [(AudioModel) -> Void] = []
    private(set) var cancelTimeCallCount = 0
    private(set) var cancelUrlCallCount = 0

    func subscribeToTimePublisher(subscription: @escaping (CMTime) -> Void) {
        timeSubscriptions.append(subscription)
    }

    func subscribeToPlayUrlPublisher(subscription: @escaping (AudioModel) -> Void) {
        // Mirrors PlayerObserver's guard, so the mock honours the same contract.
        guard urlSubscriptions.isEmpty else { return }
        urlSubscriptions.append(subscription)
    }

    func cancelTimeSubscription() {
        cancelTimeCallCount += 1
        timeSubscriptions.removeAll()
    }

    func cancelUrlSubscription() {
        cancelUrlCallCount += 1
        urlSubscriptions.removeAll()
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
