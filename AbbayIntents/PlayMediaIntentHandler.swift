//
//  PlayMediaIntentHandler.swift
//  AbbayIntents
//

import Intents

/// Result of `PlayMediaIntentHandler.decide(for:)` — the testable inner decision
/// that the public `resolveMediaItems` method then maps to opaque
/// `INPlayMediaMediaItemResolutionResult` values (which have no public accessors).
enum ResolveOutcome: Equatable {
    case unavailable
    case emptyLibrary
    case noMatch
    case singleMatch(INMediaItem)
    case disambiguation([INMediaItem])
    case fallbackBest(INMediaItem)
}

final class PlayMediaIntentHandler: NSObject, INPlayMediaIntentHandling {
    /// Internal decision method exposed for unit testing. Returns the semantic
    /// outcome before it's wrapped in opaque `INPlayMediaMediaItemResolutionResult`
    /// values (those expose no public accessors, so the wrap is untestable).
    func decide(for intent: INPlayMediaIntent) -> ResolveOutcome {
        if LaunchStateFlag.isUnavailable() {
            return .unavailable
        }

        let entries = LibrarySnapshotReader.read()
        guard !entries.isEmpty else {
            return .emptyLibrary
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
            return .noMatch
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
            return .singleMatch(items[0])
        } else if items.count <= 5 {
            return .disambiguation(items)
        } else {
            // Many-match cap: fall back to the top-ranked candidate (last-played-aware).
            return .fallbackBest(items[0])
        }
    }

    func resolveMediaItems(
        for intent: INPlayMediaIntent,
        with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void
    ) {
        switch decide(for: intent) {
        case .unavailable, .emptyLibrary, .noMatch:
            completion([.unsupported(forReason: .unsupportedMediaType)])
        case .singleMatch(let item), .fallbackBest(let item):
            completion([.success(with: item)])
        case .disambiguation(let items):
            completion([.disambiguation(with: items)])
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
