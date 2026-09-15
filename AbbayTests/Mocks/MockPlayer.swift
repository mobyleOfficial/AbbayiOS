//
//  MockPlayer.swift
//  AbbayTests
//

@testable import Abbay
import AVFoundation
import Combine
import Foundation

final class MockPlayer: PlayerProtocol {
    private let currentTimeSubject = PassthroughSubject<CMTime, Never>()
    private let playUrlSubject = PassthroughSubject<AudioModel, Never>()

    // Recordings
    var playCalls: [AudioModel] = []
    var pauseCallCount = 0
    var skipNextCallCount = 0
    var skipPreviousCallCount = 0
    var forwardSeconds: [Double] = []
    var backwardSeconds: [Double] = []
    var seekSeconds: [Double] = []
    var cleanupCallCount = 0

    // Stubs
    var url: URL?
    var currentTime: Double = 0

    var currentTimePublisher: AnyPublisher<CMTime, Never> {
        currentTimeSubject.eraseToAnyPublisher()
    }
    var playUrlSubjectPublisher: AnyPublisher<AudioModel, Never> {
        playUrlSubject.eraseToAnyPublisher()
    }

    func play(_ model: inout AudioModel) {
        playCalls.append(model)
        url = model.url
    }
    func pause() { pauseCallCount += 1 }
    func forward(withSeconds seconds: Double) { forwardSeconds.append(seconds) }
    func backward(withSeconds seconds: Double) { backwardSeconds.append(seconds) }
    func isPlaying(_ url: URL?) -> Bool { false }
    func seek(_ seconds: Double) { seekSeconds.append(seconds) }
    func cleanup() { cleanupCallCount += 1 }
    func skipToNextChapter() { skipNextCallCount += 1 }
    func skipToPreviousChapter() { skipPreviousCallCount += 1 }
}
