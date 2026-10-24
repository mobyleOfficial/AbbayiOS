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

    /// Retry-or-fail entry point used by AppIntents and Player.play. Attempts to
    /// activate the audio session and synchronizes `LaunchStateFlag` accordingly.
    /// Returns `true` when the session is now usable (caller may proceed),
    /// `false` when activation still fails (caller should surface the
    /// "audio temporarily unavailable" dialog and exit).
    ///
    /// This is the canonical recovery path — anywhere code reads
    /// `LaunchStateFlag.isUnavailable()` to gate behavior, it MUST first attempt
    /// activation via this helper. Reading the flag without retrying leaves
    /// callers stuck on a stale `true` value from a previous launch's catch
    /// branch (e.g. cold-background-launch contention) even after the audio
    /// session has since become available.
    ///
    /// `flag` and `activator` default to the container's, so App Intents (which the system builds)
    /// use what tests inject there: a throwing activator keeps the "audio unavailable" branch
    /// reachable (the real `AVAudioSession` succeeds unconditionally in the simulator).
    static func attemptActivation(
        flag: LaunchStateFlag = DependencyContainer.launchState,
        activator: AudioSessionActivatorProtocol = DependencyContainer.audioSessionActivator
    ) -> Bool {
        do {
            try activator.activate()
            flag.clear()
            return true
        } catch {
            flag.markUnavailable()
            return false
        }
    }
}
