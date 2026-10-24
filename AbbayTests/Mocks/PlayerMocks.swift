//
//  PlayerMocks.swift
//  AbbayTests
//

@testable import Abbay
import AVFoundation
import Combine
import Foundation

final class MockAudioSessionActivator: AudioSessionActivatorProtocol {
    var shouldThrow: Bool = false
    var activateCallCount = 0

    func activate() throws {
        activateCallCount += 1
        if shouldThrow { throw NSError(domain: "test", code: 1) }
    }
}

final class MockIntentDonor: IntentDonorProtocol {
    var donateCallCount = 0
    var lastDonatedModel: AudioModel?

    func donatePlayMedia(model: AudioModel) {
        donateCallCount += 1
        lastDonatedModel = model
    }
}

final class MockLibrarySnapshotWriter: LibrarySnapshotWriterProtocol {
    var writeCallCount = 0
    var refreshCallCount = 0
    var lastWrittenAudios: [AudioModel] = []

    func write(audios: [AudioModel]) {
        writeCallCount += 1
        lastWrittenAudios = audios
    }
    func refresh() { refreshCallCount += 1 }
}

final class MockBookmarkProvider: BookmarkProviderProtocol {
    var bookmarkToReturn: Data? = Data([7, 8, 9])
    var createCallCount = 0

    func createBookmarkData(for url: URL) -> Data? {
        createCallCount += 1
        return bookmarkToReturn
    }
}

final class MockSaveAudioUseCase: SaveAudioUseCaseProtocol {
    var savedModels: [AudioModel] = []

    func execute(_ model: AudioModel) throws { savedModels.append(model) }
}

final class MockSavePlaybackPositionUseCase: SavePlaybackPositionUseCaseProtocol {
    struct Call: Equatable {
        let url: URL?
        let currentTime: Double
        let bookmarkData: Data?
    }

    var calls: [Call] = []

    func execute(url: URL?, currentTime: Double, bookmarkData: Data?) {
        calls.append(Call(url: url, currentTime: currentTime, bookmarkData: bookmarkData))
    }
}

/// A player whose publishers count their subscribers, for the "one source subscribes once" proof.
/// The counts go up in `handleEvents(receiveSubscription:)`, so they measure subscriptions made,
/// not values delivered.
final class CountingMockPlayer: PlayerProtocol {
    private let currentTimeSubject = PassthroughSubject<CMTime, Never>()
    private let playUrlSubject = PassthroughSubject<AudioModel, Never>()
    private let isPlayingSubject = PassthroughSubject<Bool, Never>()

    private(set) var timeSubscriptionCount = 0
    private(set) var urlSubscriptionCount = 0
    private(set) var playingSubscriptionCount = 0

    // Stubs
    var url: URL?
    var currentTime: Double = 0
    var isPlayingResult = false

    var currentTimePublisher: AnyPublisher<CMTime, Never> {
        currentTimeSubject
            .handleEvents(receiveSubscription: { [weak self] _ in self?.timeSubscriptionCount += 1 })
            .eraseToAnyPublisher()
    }
    var playUrlSubjectPublisher: AnyPublisher<AudioModel, Never> {
        playUrlSubject
            .handleEvents(receiveSubscription: { [weak self] _ in self?.urlSubscriptionCount += 1 })
            .eraseToAnyPublisher()
    }
    var isPlayingPublisher: AnyPublisher<Bool, Never> {
        isPlayingSubject
            .handleEvents(receiveSubscription: { [weak self] _ in self?.playingSubscriptionCount += 1 })
            .eraseToAnyPublisher()
    }

    // MARK: - Test drivers
    /// Like `Player`, which holds the new book before announcing it.
    func emitPlayUrl(_ model: AudioModel) {
        url = model.url
        playUrlSubject.send(model)
    }
    func emitTime(_ seconds: Double) { currentTimeSubject.send(CMTime(seconds: seconds, preferredTimescale: 600)) }
    func emitPlaying(_ isPlaying: Bool) { isPlayingSubject.send(isPlaying) }

    // MARK: - PlayerProtocol
    func play(_ model: inout AudioModel) { url = model.url }
    func pause() {}
    func forward(withSeconds seconds: Double) {}
    func backward(withSeconds seconds: Double) {}
    func isPlaying(_ url: URL?) -> Bool { isPlayingResult }
    func seek(_ seconds: Double) {}
    func cleanup() {}
    func unload() { url = nil }
    func skipToNextChapter() {}
    func skipToPreviousChapter() {}
    func playChapter(at index: Int) -> Bool { false }
}
