//
//  InAppPlayMediaHandler.swift
//  Abbay
//

import Intents

/// Runs the full SiriKit lifecycle for `INPlayMediaIntent` inside the app.
///
/// The app declares `INIntentsSupported`, so iOS dispatches media requests here
/// rather than to the AbbayIntents extension. Supplying only
/// `application(_:handle:)` gives the system a bare completion with no resolve or
/// confirm step, and Siri reports a generic error even when playback starts.
/// Returning this object from `application(_:handlerFor:)` gives the system the
/// whole lifecycle it expects: resolve the spoken title to a media item, confirm
/// readiness, then play.
final class InAppPlayMediaHandler: NSObject, INPlayMediaIntentHandling {
    private let router: IntentRouterProtocol
    private let snapshotReader: () -> [LibrarySnapshotEntry]

    init(
        router: IntentRouterProtocol = IntentRouter(),
        snapshotReader: @escaping () -> [LibrarySnapshotEntry] = { LibrarySnapshotReader.read() }
    ) {
        self.router = router
        self.snapshotReader = snapshotReader
    }

    /// The testable half of `resolveMediaItems`: `INPlayMediaMediaItemResolutionResult`
    /// exposes no accessors, so the decision is taken here and only wrapped below.
    func pick(for intent: INPlayMediaIntent) -> INMediaItem? {
        let audios = MediaSearchResolver.audios(from: snapshotReader())
        let picked = MediaSearchResolver.candidates(
            mediaName: intent.mediaSearch?.mediaName ?? "",
            audios: audios,
            lastPlayedURL: LastPlayedStore.lastPlayedURL()
        ).first
        guard let picked, let url = picked.url else { return nil }
        return INMediaItem(
            identifier: url.absoluteString,
            title: picked.title,
            type: .audioBook,
            artwork: nil
        )
    }

    func resolveMediaItems(
        for intent: INPlayMediaIntent,
        with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void
    ) {
        guard let item = pick(for: intent) else {
            SiriDiagnostics.record("inapp resolve → unsupported")
            completion([.unsupported(forReason: .unsupportedMediaType)])
            return
        }
        SiriDiagnostics.record("inapp resolve → success")
        completion([.success(with: item)])
    }

    func confirm(
        intent: INPlayMediaIntent,
        completion: @escaping (INPlayMediaIntentResponse) -> Void
    ) {
        SiriDiagnostics.record("inapp confirm → ready")
        completion(INPlayMediaIntentResponse(code: .ready, userActivity: nil))
    }

    func handle(
        intent: INPlayMediaIntent,
        completion: @escaping (INPlayMediaIntentResponse) -> Void
    ) {
        let response = router.handle(intent)
        SiriDiagnostics.record("inapp handle → code=\(response.code.rawValue)")
        completion(response)
    }
}
