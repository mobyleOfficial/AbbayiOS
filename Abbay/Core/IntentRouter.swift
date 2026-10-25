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
    private let lastPlayed: LastPlayedStore
    private let launchState: LaunchStateFlag
    private let diagnostics: SiriDiagnostics
    private let resolveBookmark: (Data?) -> ResolvedBookmark?

    init(
        loadAudio: LoadAudioUseCaseProtocol = LoadAudioUseCase(),
        snapshotWriter: LibrarySnapshotWriterProtocol = LibrarySnapshotWriter.shared,
        snapshotReader: @escaping () -> [LibrarySnapshotEntry] = { LibrarySnapshotReader.shared.read() },
        player: @escaping () -> PlayerProtocol = { DependencyContainer.shared.player },
        lastPlayed: LastPlayedStore = .shared,
        launchState: LaunchStateFlag = .shared,
        diagnostics: SiriDiagnostics = .shared,
        resolveBookmark: @escaping (Data?) -> ResolvedBookmark? = URL.resolveBookmarkRefreshing
    ) {
        self.loadAudio = loadAudio
        self.snapshotWriter = snapshotWriter
        self.snapshotReader = snapshotReader
        self.player = player
        self.lastPlayed = lastPlayed
        self.launchState = launchState
        self.diagnostics = diagnostics
        self.resolveBookmark = resolveBookmark
    }

    func handle(_ intent: INPlayMediaIntent) -> INPlayMediaIntentResponse {
        diagnostics.record("app handleInApp received")
        if launchState.isUnavailable() {
            return INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil)
        }
        guard let identifier = identifier(for: intent) else {
            diagnostics.record("app handleInApp unresolved")
            return INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil)
        }

        // The identifier is the book's identity, its row's URL (#186). One donated or published
        // before that can be where a moved book's file resolved then: find its row by bookmark.
        guard var model = loadAudio.execute(url: URL(string: identifier))
                ?? loadAudio.execute(url: rowURL(resolvingTo: identifier)) else {
            diagnostics.record("app handleInApp load failed")
            if let saved = lastPlayed.lastPlayedURL(), saved.absoluteString == identifier {
                lastPlayed.save(url: nil)
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
            lastPlayedURL: lastPlayed.lastPlayedURL()
        ).first
        diagnostics.record(
            "app resolved in-app library=\(audios.count) matched=\(picked != nil)"
        )
        return picked?.url?.absoluteString
    }

    /// The row URL of the snapshot book whose bookmark resolves to `identifier`: a legacy id, where
    /// a moved book's file resolved when it was donated or published. Only asked on a miss. (A
    /// stale bookmark needs nothing here: loading the book saves the fresh one, #146.)
    private func rowURL(resolvingTo identifier: String) -> URL? {
        guard let wanted = URL(string: identifier) else { return nil }
        let match = snapshotReader().first { entry in
            guard entry.urlString != identifier, let bookmark = entry.bookmarkData else { return false }
            return resolveBookmark(bookmark)?.url == wanted
        }
        return match.flatMap { URL(string: $0.urlString) }
    }
}
