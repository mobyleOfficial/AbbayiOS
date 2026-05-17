//
//  AudioSessionActivator.swift
//  Abbay
//

import AVFoundation

protocol AudioSessionActivatorProtocol {
    func activate() throws
}

final class AudioSessionActivator: AudioSessionActivatorProtocol {
    func activate() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback)
        try AVAudioSession.sharedInstance().setActive(true)
    }
}
