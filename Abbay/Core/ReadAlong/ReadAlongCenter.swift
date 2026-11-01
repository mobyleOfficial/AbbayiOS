//
//  ReadAlongCenter.swift
//  Abbay
//

import Foundation
import Observation

/// Read-along's app-wide services: the speech engine, where transcripts are kept, and the settings
/// that switch the feature and hold each book's language. The player asks it for a session per
/// screen rather than building one, so tests and `-seedReadAlong` swap the engine in one place.
///
/// The transcriber is nil below iOS 26, where the speech engine doesn't exist, and where Speech
/// can't transcribe on the hardware (the Simulator among them): the feature is then unavailable,
/// Settings shows no Experimental section and the player no Text pill.
@MainActor
@Observable
final class ReadAlongCenter {
    @ObservationIgnored private let transcriber: ReadAlongTranscribing?
    @ObservationIgnored private let store: ReadAlongStore
    @ObservationIgnored private let settings: AppSettings
    /// Finds chapters in the audio of imported books that have none, with the same engine.
    let chapters: ChapterFinder

    /// Built by the dependency container, off the main actor's checks like `PlaybackCenter`.
    /// `playback` is where found chapters reach the loaded book; nil in tests that don't need it.
    nonisolated init(
        transcriber: ReadAlongTranscribing?,
        store: ReadAlongStore,
        settings: AppSettings,
        playback: PlaybackCenter? = nil
    ) {
        self.transcriber = transcriber
        self.store = store
        self.settings = settings
        chapters = ChapterFinder(transcriber: transcriber, settings: settings, playback: playback)
    }

    /// Whether this device can transcribe at all (iOS 26+, with an engine that runs here).
    var isAvailable: Bool {
        transcriber != nil
    }

    /// A session for one player screen. A session stops itself when Read-along is turned off.
    func makeSession() -> ReadAlongSession {
        ReadAlongSession(transcriber: transcriber, store: store, settings: settings)
    }
}
