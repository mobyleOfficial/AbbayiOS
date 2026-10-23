//
//  PlayerMocks.swift
//  AbbayTests
//

@testable import Abbay
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
