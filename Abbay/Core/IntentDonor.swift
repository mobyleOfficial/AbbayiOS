//
//  IntentDonor.swift
//  Abbay
//

import Intents

protocol IntentDonorProtocol {
    func donatePlayMedia(model: AudioModel)
}

/// Donates `INPlayMediaIntent` interactions so the system sees ongoing listening: at play start,
/// on pause and at chapter boundaries (#127). A repeat for the same book inside `repeatWindow` is
/// dropped (play then pause, a burst of chapter skips), and doesn't restart the window.
final class IntentDonor: IntentDonorProtocol {
    // var so tests can rebind
    static var shared: IntentDonorProtocol = IntentDonor()

    static let repeatWindow: TimeInterval = 2 * 60

    private let now: () -> Date
    /// Donates the interaction and calls back with the system's outcome.
    private let donate: (INInteraction, @escaping (Error?) -> Void) -> Void
    private let lock = NSLock()
    /// The last donation made, not the last one asked for.
    private var lastDonation: (identifier: String, date: Date)?

    init(
        now: @escaping () -> Date = Date.init,
        donate: @escaping (INInteraction, @escaping (Error?) -> Void) -> Void = { $0.donate(completion: $1) }
    ) {
        self.now = now
        self.donate = donate
    }

    func donatePlayMedia(model: AudioModel) {
        guard shouldDonate(identifier: Self.mediaIdentifier(for: model)) else { return }
        let intent = buildIntent(for: model)
        let response = INPlayMediaIntentResponse(code: .success, userActivity: nil)
        donate(INInteraction(intent: intent, response: response), Self.logOutcome)
    }

    /// A failed donation silently stops Siri learning to prefer Abbay (#157), so it is logged.
    /// The error's domain and code only: the description can carry the title.
    private static func logOutcome(_ error: Error?) {
        guard let error = error as NSError? else { return }
        Log.siri.error("donation failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
    }

    private func shouldDonate(identifier: String) -> Bool {
        let date = now()
        return lock.withLock {
            if let lastDonation, lastDonation.identifier == identifier,
               date.timeIntervalSince(lastDonation.date) < Self.repeatWindow {
                return false
            }
            lastDonation = (identifier, date)
            return true
        }
    }

    private static func mediaIdentifier(for model: AudioModel) -> String {
        model.url?.absoluteString ?? ""
    }

    // Exposed for tests
    func buildIntent(for model: AudioModel) -> INPlayMediaIntent {
        let mediaItem = INMediaItem(
            identifier: Self.mediaIdentifier(for: model),
            title: model.title,
            type: .audioBook,
            artwork: nil
        )
        return INPlayMediaIntent(
            mediaItems: [mediaItem],
            mediaContainer: nil,
            playShuffled: nil,
            playbackRepeatMode: .none,
            resumePlayback: nil,
            playbackQueueLocation: .now,
            playbackSpeed: nil,
            mediaSearch: INMediaSearch(
                mediaType: .audioBook,
                sortOrder: .unknown,
                mediaName: model.title,
                artistName: nil,
                albumName: nil,
                genreNames: nil,
                moodNames: nil,
                releaseDate: nil,
                reference: .unknown,
                mediaIdentifier: nil
            )
        )
    }
}
