//
//  IntentRouter.swift
//  Abbay
//

import Intents

protocol IntentRouterProtocol {
    func handle(_ intent: INPlayMediaIntent) -> INPlayMediaIntentResponse
}

final class IntentRouter: IntentRouterProtocol {
    private let loadAudio: LoadAudioUseCaseProtocol
    private let snapshotWriter: LibrarySnapshotWriterProtocol
    private let snapshotReader: () -> [LibrarySnapshotEntry]
    private let player: () -> PlayerProtocol

    init(
        loadAudio: LoadAudioUseCaseProtocol = LoadAudioUseCase(),
        snapshotWriter: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter.shared,
        snapshotReader: @escaping () -> [LibrarySnapshotEntry] = { LibrarySnapshotReader.read() },
        player: @escaping () -> PlayerProtocol = { DependencyContainer.shared.player }
    ) {
        self.loadAudio = loadAudio
        self.snapshotWriter = snapshotWriter
        self.snapshotReader = snapshotReader
        self.player = player
    }

    func handle(_ intent: INPlayMediaIntent) -> INPlayMediaIntentResponse {
        SiriDiagnostics.record("app handleInApp received")
        if LaunchStateFlag.isUnavailable() {
            return INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil)
        }
        guard let identifier = identifier(for: intent) else {
            SiriDiagnostics.record("app handleInApp unresolved")
            return INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil)
        }

        // A stale or relocated bookmark resolves to a URL that is no longer the key
        // the library was stored under, so fall back to the identifier itself
        // before declaring the book unplayable.
        let resolvedURL = resolveURL(from: identifier)
        let fallbackURL = URL(string: identifier)
        guard var model = loadAudio.execute(url: resolvedURL)
                ?? loadAudio.execute(url: fallbackURL) else {
            SiriDiagnostics.record("app handleInApp load failed")
            if let saved = LastPlayedStore.lastPlayedURL(), saved.absoluteString == identifier {
                LastPlayedStore.save(url: nil)
            }
            snapshotWriter.refresh()
            return INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil)
        }

        player().play(&model)
        return INPlayMediaIntentResponse(code: .success, userActivity: nil)
    }

    /// The book to play.
    ///
    /// When the AbbayIntents extension handles the request it has already run
    /// `resolveMediaItems`, so the intent arrives carrying a resolved media item.
    /// But the app also declares `INIntentsSupported`, and on that path iOS
    /// dispatches `INPlayMediaIntent` straight here with nothing resolved — only
    /// the raw `mediaSearch`. Matching here too keeps both paths working; without
    /// it the request fails and Siri reports a generic error.
    private func identifier(for intent: INPlayMediaIntent) -> String? {
        if let resolved = intent.mediaItems?.first?.identifier, !resolved.isEmpty {
            return resolved
        }
        let audios = MediaSearchResolver.audios(from: snapshotReader())
        let picked = MediaSearchResolver.candidates(
            mediaName: intent.mediaSearch?.mediaName ?? "",
            audios: audios,
            lastPlayedURL: LastPlayedStore.lastPlayedURL()
        ).first
        SiriDiagnostics.record(
            "app resolved in-app library=\(audios.count) matched=\(picked != nil)"
        )
        return picked?.url?.absoluteString
    }

    private func resolveURL(from identifier: String) -> URL? {
        let entries = snapshotReader()
        if let match = entries.first(where: { $0.urlString == identifier }),
           let bookmark = match.bookmarkData {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                // If the bookmark is stale, ask LibrarySnapshotWriter to refresh so the
                // next read picks up a freshly-recreated bookmark from AudioModel state.
                // Player.play's lazy-bookmark migration handles non-nil but stale data
                // via the same refresh path when the model is loaded.
                if isStale {
                    snapshotWriter.refresh()
                }
                return resolved
            }
        }
        return URL(string: identifier)
    }
}
