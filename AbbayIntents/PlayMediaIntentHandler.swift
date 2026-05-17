//
//  PlayMediaIntentHandler.swift
//  AbbayIntents
//
//  Stub — replaced by the real implementation in T22.
//

import Intents

final class PlayMediaIntentHandler: NSObject, INPlayMediaIntentHandling {
    func resolveMediaItems(
        for intent: INPlayMediaIntent,
        with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void
    ) {
        completion([.unsupported(forReason: .unsupportedMediaType)])
    }

    func handle(
        intent: INPlayMediaIntent,
        completion: @escaping (INPlayMediaIntentResponse) -> Void
    ) {
        completion(INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil))
    }
}
