//
//  PlayMediaIntentHandler.swift
//  AbbayIntents
//

import Intents

final class PlayMediaIntentHandler: NSObject, INPlayMediaIntentHandling {
    func resolveMediaItems(
        for intent: INPlayMediaIntent,
        with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void
    ) {
        if LaunchStateFlag.isUnavailable() {
            completion([.unsupported(forReason: .unsupportedMediaType)])
            return
        }

        let entries = LibrarySnapshotReader.read()
        guard !entries.isEmpty else {
            completion([.unsupported(forReason: .unsupportedMediaType)])
            return
        }

        let mediaName = intent.mediaSearch?.mediaName ?? ""
        let lastPlayedString = AppGroup.defaults.string(forKey: LastPlayedStore.key)
        let lastPlayedURL = lastPlayedString.flatMap { URL(string: $0) }

        let audios: [AudioModel] = entries.compactMap { entry in
            guard let url = URL(string: entry.urlString) else { return nil }
            var model = AudioModel(url: url)
            model.title = entry.title
            return model
        }

        let candidates = matchAll(input: mediaName, audios: audios, lastPlayedURL: lastPlayedURL)
        if candidates.isEmpty {
            completion([.unsupported(forReason: .unsupportedMediaType)])
            return
        }

        let items: [INMediaItem] = candidates.map { audio in
            INMediaItem(
                identifier: audio.url?.absoluteString ?? "",
                title: audio.title,
                type: .audioBook,
                artwork: nil
            )
        }

        if items.count == 1 {
            completion([.success(with: items[0])])
        } else if items.count <= 5 {
            completion([.disambiguation(with: items)])
        } else {
            // Many-match cap: fall back to the top-ranked candidate (last-played-aware).
            completion([.success(with: items[0])])
        }
    }

    func handle(
        intent: INPlayMediaIntent,
        completion: @escaping (INPlayMediaIntentResponse) -> Void
    ) {
        if LaunchStateFlag.isUnavailable() {
            // TODO(T21): Replace with PlayMediaIntentResponse.unavailable once the
            // .intentdefinition is created in Xcode. See AbbayIntents/PLAYMEDIAINTENT_TODO.md.
            completion(INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil))
            return
        }

        // Defense-in-depth: per SiriKit lifecycle, when resolveMediaItems returns all-unsupported
        // (no-match path), Siri normally does NOT call handle — it speaks the failure dialog tied
        // to the Resolution Result + .intentdefinition Response template (set up in T21) directly.
        // This branch catches the unlikely case where handle is invoked with empty mediaItems.
        if intent.mediaItems?.isEmpty ?? true {
            completion(INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil))
            return
        }

        completion(INPlayMediaIntentResponse(code: .handleInApp, userActivity: nil))
    }
}
