//
//  BookVolumeTests.swift
//  AbbayTests
//

@testable import Abbay
import AVFoundation
import XCTest

/// The boost past 100% (#297): how the capsule's track maps to the level (0–100% gets the bottom
/// two thirds, 100–200% is squeezed into the top third, with a sticky notch at 100%), how the level
/// splits between the player's volume and the boost's gain, and the boost's limiter.
final class BookVolumeTests: XCTestCase {
    // MARK: - Track mapping

    func test_track_givesDimmingTheBottomTwoThirds() {
        XCTAssertEqual(BookVolume.notch, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(BookVolume.track(for: 0), 0)
        XCTAssertEqual(BookVolume.track(for: 1), BookVolume.notch, accuracy: 0.0001)
        XCTAssertEqual(BookVolume.track(for: 0.5), BookVolume.notch / 2, accuracy: 0.0001)
        XCTAssertEqual(BookVolume.track(for: 2), 1, accuracy: 0.0001)
        XCTAssertEqual(BookVolume.track(for: 1.5), (BookVolume.notch + 1) / 2, accuracy: 0.0001)
    }

    func test_volumeAtTrack_isTheInverse_snapped() {
        XCTAssertEqual(BookVolume.volume(atTrack: 0), 0)
        XCTAssertEqual(BookVolume.volume(atTrack: 1), 2)
        XCTAssertEqual(BookVolume.volume(atTrack: BookVolume.notch / 2), 0.5)
        XCTAssertEqual(BookVolume.volume(atTrack: (BookVolume.notch + 1) / 2), 1.5)
        XCTAssertEqual(BookVolume.volume(atTrack: -0.4), 0, "past the bottom")
        XCTAssertEqual(BookVolume.volume(atTrack: 1.4), 2, "past the top")
    }

    /// Near the notch a drag sticks at exactly 100%, from either side.
    func test_volumeAtTrack_sticksAtFullNearTheNotch() {
        let notch = BookVolume.notch
        XCTAssertEqual(BookVolume.volume(atTrack: notch), 1)
        XCTAssertEqual(BookVolume.volume(atTrack: notch + BookVolume.stickiness * 0.9), 1)
        XCTAssertEqual(BookVolume.volume(atTrack: notch - BookVolume.stickiness * 0.9), 1)
        XCTAssertGreaterThan(BookVolume.volume(atTrack: notch + BookVolume.stickiness * 1.5), 1)
        XCTAssertLessThan(BookVolume.volume(atTrack: notch - BookVolume.stickiness * 1.5), 1)
    }

    // MARK: - Player volume and boost

    func test_level_splitsIntoPlayerVolumeAndBoostGain() {
        XCTAssertEqual(BookVolume.playerVolume(0.4), 0.4)
        XCTAssertEqual(BookVolume.boostGain(0.4), 1, "no boost while dimmed")
        XCTAssertEqual(BookVolume.playerVolume(1), 1)
        XCTAssertEqual(BookVolume.boostGain(1), 1)
        XCTAssertEqual(BookVolume.playerVolume(1.6), 1)
        XCTAssertEqual(BookVolume.boostGain(1.6), 1.6, accuracy: 0.0001)
        XCTAssertTrue(BookVolume.isBoosted(1.05))
        XCTAssertFalse(BookVolume.isBoosted(1))
    }

    // MARK: - Limiter

    func test_boost_atUnityGain_leavesSamplesUntouched() {
        var samples: [Float] = [0, 0.5, -0.99, 1, -1]
        let original = samples

        samples.withUnsafeMutableBufferPointer { VolumeBoost.apply(gain: 1, to: $0) }

        XCTAssertEqual(samples, original)
    }

    func test_boost_scalesQuietSamplesByTheGain() {
        var samples: [Float] = [0.1, -0.2, 0]

        samples.withUnsafeMutableBufferPointer { VolumeBoost.apply(gain: 2, to: $0) }

        XCTAssertEqual(samples[0], 0.2, accuracy: 0.0001)
        XCTAssertEqual(samples[1], -0.4, accuracy: 0.0001)
        XCTAssertEqual(samples[2], 0)
    }

    /// Loud samples pushed past the knee are bent under 1, never clipped flat, and keep their order
    /// and sign.
    func test_boost_limitsLoudSamplesBelowFullScale() {
        var samples: [Float] = [0.6, 0.9, 1, -1]

        samples.withUnsafeMutableBufferPointer { VolumeBoost.apply(gain: 2, to: $0) }

        for sample in samples {
            XCTAssertLessThan(abs(sample), 1)
        }
        XCTAssertLessThan(samples[0], samples[1])
        XCTAssertLessThan(samples[1], samples[2])
        XCTAssertEqual(samples[3], -samples[2], accuracy: 0.0001)
    }
}

/// The boost's tap on a real item: the fixture's audio track loads and the item gets an audio mix
/// carrying the tap. (That the tap makes it louder is a listening check; the maths is above.)
final class VolumeBoostAttachTests: XCTestCase {
    func test_attach_givesARealItemAnAudioMixWithTheTap() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Christmastide", withExtension: "m4b"))
        let item = AVPlayerItem(url: url)
        let boost = VolumeBoost()

        boost.attach(to: item)

        let attached = expectation(description: "the item gets the boost's audio mix")
        let deadline = Date().addingTimeInterval(10)
        func poll() {
            if item.audioMix?.inputParameters.first?.audioTapProcessor != nil {
                attached.fulfill()
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
            }
        }
        poll()
        wait(for: [attached], timeout: 11)
    }
}
