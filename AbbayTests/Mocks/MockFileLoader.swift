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

    func subscribeToTimePublisher(subscription: @escaping (CMTime) -> Void) {}
    func subscribeToPlayUrlPublisher(subscription: @escaping (AudioModel) -> Void) {}
    func cancelTimeSubscription() {}
}
