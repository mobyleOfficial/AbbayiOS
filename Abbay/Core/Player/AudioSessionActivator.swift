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
    /// `makeActivator` is the injection seam: tests rebind it to a stub that
    /// throws so the "audio unavailable" branch stays reachable (the real
    /// `AVAudioSession` succeeds unconditionally in the simulator).
    static var makeActivator: () -> AudioSessionActivatorProtocol = { AudioSessionActivator() }

    /// `flag` defaults to the container's, so App Intents (which the system builds) use the
    /// store tests inject there.
    static func attemptActivation(flag: LaunchStateFlag = DependencyContainer.launchState) -> Bool {
        do {
            try makeActivator().activate()
            flag.clear()
            return true
        } catch {
            flag.markUnavailable()
            return false
        }
    }
}
