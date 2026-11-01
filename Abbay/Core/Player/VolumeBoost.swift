//
//  VolumeBoost.swift
//  Abbay
//

import AVFoundation
import MediaToolbox
import os

/// Makes a quiet recording louder: Abbay's volume past 100%, up to 200% (#297). `AVPlayer.volume`
/// stops at 1, so this multiplies the samples themselves, through an audio-processing tap on each
/// player item, with a soft limiter so a loud passage is squashed rather than clipped.
///
/// Every item gets a tap, so the boost applies live as the slider moves; at 100% or below the tap
/// leaves the samples untouched. An item whose audio the tap can't read (no audio track, a format
/// other than 32-bit float) plays unchanged, never silenced.
final class VolumeBoost {
    /// Read on the audio thread by every tap.
    private let gainBox = GainBox()

    /// What the samples are multiplied by, at least 1.
    var gain: Double {
        get { Double(gainBox.value) }
        set { gainBox.value = Float(max(newValue, 1)) }
    }

    /// Gives `item` a tap reading `gain`, once its audio track has loaded.
    func attach(to item: AVPlayerItem) {
        let box = gainBox
        let asset = item.asset
        Task { @MainActor [weak item] in
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let item,
                  let tap = Self.makeTap(reading: box)
            else { return }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            item.audioMix = mix
        }
    }

    /// Multiplies by `gain`; past the knee the sample is bent towards ±1 (`tanh`), so it never
    /// reaches full scale and never clips flat. A gain of 1 or less leaves the samples untouched.
    static func apply(gain: Float, to samples: UnsafeMutableBufferPointer<Float>) {
        guard gain > 1 else { return }
        let knee: Float = 0.8
        let headroom = 1 - knee
        for index in samples.indices {
            let boosted = samples[index] * gain
            let magnitude = abs(boosted)
            guard magnitude > knee else {
                samples[index] = boosted
                continue
            }
            let bent = knee + headroom * tanh((magnitude - knee) / headroom)
            samples[index] = boosted < 0 ? -bent : bent
        }
    }

    // MARK: - Tap

    private static func makeTap(reading box: GainBox) -> MTAudioProcessingTap? {
        let context = Unmanaged.passRetained(TapContext(box: box)).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: context,
            init: { _, clientInfo, storage in
                storage.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                let context = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue()
                let description = format.pointee
                context.isFloat32 = description.mFormatFlags & kAudioFormatFlagIsFloat != 0
                    && description.mBitsPerChannel == 32
            },
            unprepare: nil,
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut) == noErr
                else { return }
                let context = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue()
                let gain = context.box.value
                guard context.isFloat32, gain > 1 else { return }
                for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
                    guard let data = buffer.mData else { continue }
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    let samples = UnsafeMutableBufferPointer(
                        start: data.assumingMemoryBound(to: Float.self),
                        count: count
                    )
                    VolumeBoost.apply(gain: gain, to: samples)
                }
            }
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )
        guard status == noErr, let tap else {
            Unmanaged<TapContext>.fromOpaque(context).release()
            return nil
        }
        return tap
    }
}

/// The gain every tap reads, behind a lock: written on the main thread, read on the audio thread.
private final class GainBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<Float>(initialState: 1)

    var value: Float {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}

/// One tap's state, owned by the tap (released in `finalize`).
private final class TapContext {
    let box: GainBox
    /// Set in `prepare`: the tap only touches 32-bit float samples.
    var isFloat32 = false

    init(box: GainBox) {
        self.box = box
    }
}
