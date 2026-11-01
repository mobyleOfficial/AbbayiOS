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
    private let isPlayingSubject = PassthroughSubject<Bool, Never>()

    // Recordings
    var playCalls: [AudioModel] = []
    var pauseCallCount = 0
    var skipNextCallCount = 0
    var skipPreviousCallCount = 0
    var forwardSeconds: [Double] = []
    var backwardSeconds: [Double] = []
    var seekSeconds: [Double] = []
    var cleanupCallCount = 0
    var unloadCallCount = 0

    // Stubs
    var url: URL?
    var currentTime: Double = 0

    var currentTimePublisher: AnyPublisher<CMTime, Never> {
        currentTimeSubject.eraseToAnyPublisher()
    }
    var playUrlSubjectPublisher: AnyPublisher<AudioModel, Never> {
        playUrlSubject.eraseToAnyPublisher()
    }
    var isPlayingPublisher: AnyPublisher<Bool, Never> {
        isPlayingSubject.eraseToAnyPublisher()
    }

    // MARK: - Test drivers
    //
    // The subjects are private, so this is the only way to exercise a real `PlayerObserver`
    // sitting on top of a mock player.

    /// Like `Player`, which holds the new book before announcing it.
    func emitPlayUrl(_ model: AudioModel) {
        url = model.url
        playUrlSubject.send(model)
    }

    func emitTime(_ seconds: Double) {
        currentTimeSubject.send(CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func emitPlaying(_ isPlaying: Bool) {
        isPlayingSubject.send(isPlaying)
    }

    /// `false` stands for a book `Player.play` refuses (it reports a notice and loads nothing).
    var loadsOnPlay = true

    func play(_ model: inout AudioModel) {
        playCalls.append(model)
        if loadsOnPlay {
            url = model.url
        }
    }
    func pause() { pauseCallCount += 1 }
    func forward(withSeconds seconds: Double) { forwardSeconds.append(seconds) }
    func backward(withSeconds seconds: Double) { backwardSeconds.append(seconds) }
    /// Defaults to false, preserving the previous hard-coded behaviour.
    var isPlayingResult = false

    func isPlaying(_ url: URL?) -> Bool { isPlayingResult }
    func seek(_ seconds: Double) { seekSeconds.append(seconds) }
    func cleanup() { cleanupCallCount += 1 }
    func unload() {
        unloadCallCount += 1
        url = nil
    }
    func skipToNextChapter() { skipNextCallCount += 1 }
    func skipToPreviousChapter() { skipPreviousCallCount += 1 }

    /// Chapter indices requested through `playChapter(at:)`.
    var playChapterCalls = [Int]()
    /// What `playChapter(at:)` should report — mirrors "a book is loaded and the
    /// index exists".
    var playChapterResult = true

    func playChapter(at index: Int) -> Bool {
        playChapterCalls.append(index)
        return playChapterResult
    }

    /// Where `resumeTime(ofChapter:in:)` says a chapter resumes; its start when not set.
    var resumeTimes: [Int: Double] = [:]

    func resumeTime(ofChapter index: Int, in book: AudioModel) -> Double {
        resumeTimes[index] ?? book.chapters[index].startTime
    }

    /// Rates passed to `setPlaybackRate(_:)`.
    var rateCalls = [Double]()
    var playbackRate: Double = 1

    func setPlaybackRate(_ rate: Double) {
        rateCalls.append(rate)
        playbackRate = rate
    }

    /// Levels passed to `setVolume(_:)`.
    var volumeCalls = [Double]()
    var volume: Double = 1

    func setVolume(_ volume: Double) {
        volumeCalls.append(volume)
        self.volume = volume
    }
}
