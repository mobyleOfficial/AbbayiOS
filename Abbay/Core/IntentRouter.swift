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
        guard let identifier = intent.mediaItems?.first?.identifier else {
            return INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil)
        }

        let resolvedURL = resolveURL(from: identifier)
        guard var model = loadAudio.execute(url: resolvedURL) else {
            if let saved = LastPlayedStore.lastPlayedURL(), saved.absoluteString == identifier {
                LastPlayedStore.save(url: nil)
            }
            snapshotWriter.refresh()
            return INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil)
        }

        player().play(&model)
        return INPlayMediaIntentResponse(code: .success, userActivity: nil)
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
