//
//  IntentDonor.swift
//  Abbay
//

import Intents

protocol IntentDonorProtocol {
    func donatePlayMedia(model: AudioModel)
}

final class IntentDonor: IntentDonorProtocol {
    // var so tests can rebind
    static var shared: IntentDonorProtocol = IntentDonor()

    func donatePlayMedia(model: AudioModel) {
        let intent = buildIntent(for: model)
        let response = INPlayMediaIntentResponse(code: .success, userActivity: nil)
        INInteraction(intent: intent, response: response).donate(completion: nil)
    }

    // Exposed for tests
    func buildIntent(for model: AudioModel) -> INPlayMediaIntent {
        let mediaItem = INMediaItem(
            identifier: model.url?.absoluteString ?? "",
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
