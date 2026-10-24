//
//  PlayMediaIntentHandler.swift
//  AbbayIntents
//

import Intents
import os.log

private let log = OSLog(subsystem: "com.edyuto.Abbay.AbbayIntents", category: "PlayMediaIntent")

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
    private let lastPlayed: LastPlayedStore
    private let launchState: LaunchStateFlag
    private let librarySnapshot: LibrarySnapshotReader
    private let diagnostics: SiriDiagnostics

    /// The App Group stores, injected. `IntentHandler` takes the defaults (the shared App Group);
    /// tests pass in-memory ones.
    init(
        lastPlayed: LastPlayedStore = .shared,
        launchState: LaunchStateFlag = .shared,
        librarySnapshot: LibrarySnapshotReader = .shared,
        diagnostics: SiriDiagnostics = .shared
    ) {
        self.lastPlayed = lastPlayed
        self.launchState = launchState
        self.librarySnapshot = librarySnapshot
        self.diagnostics = diagnostics
    }

    /// Internal decision method exposed for unit testing. Returns the semantic
    /// outcome before it's wrapped in opaque `INPlayMediaMediaItemResolutionResult`
    /// values (those expose no public accessors, so the wrap is untestable).
    func decide(for intent: INPlayMediaIntent) -> ResolveOutcome {
        let mediaName = intent.mediaSearch?.mediaName ?? ""
        let flagValue = launchState.isUnavailable()
        os_log(
            // The spoken title is user speech, so it stays private in the log.
            // Xcode shows it anyway while a debugger is attached.
            "decide entered: mediaName=%{private}@ flag=%{public}@ suite=%{public}@",
            log: log, type: .info,
            mediaName, String(describing: flagValue), AppGroup.suiteName
        )

        diagnostics.record("ext decide entered titleless=\(mediaName.isEmpty)")

        if flagValue {
            os_log("decide → unavailable (flag set)", log: log, type: .info)
            diagnostics.record("ext outcome=unavailable")
            return .unavailable
        }

        let entries = librarySnapshot.read()
        os_log("decide read snapshot: %{public}d entries", log: log, type: .info, entries.count)
        guard !entries.isEmpty else {
            os_log("decide → emptyLibrary", log: log, type: .info)
            diagnostics.record("ext outcome=emptyLibrary")
            return .emptyLibrary
        }

        // Go through LastPlayedStore rather than reading the App Group suite
        // directly: the store also consults the phase-1 `.standard` fallback.
        let lastPlayedURL = lastPlayed.lastPlayedURL()
        os_log(
            "decide lastPlayed=%{private}@",
            log: log, type: .info,
            lastPlayedURL?.absoluteString ?? "<nil>"
        )

        let audios = MediaSearchResolver.audios(from: entries)

        let candidates = resolveCandidates(
            mediaName: mediaName,
            audios: audios,
            lastPlayedURL: lastPlayedURL
        )
        if candidates.isEmpty {
            os_log("decide → noMatch", log: log, type: .info)
            diagnostics.record("ext outcome=noMatch")
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

        diagnostics.record("ext outcome=matched count=\(items.count)")

        if items.count == 1 {
            return .singleMatch(items[0])
        } else if items.count <= 5 {
            return .disambiguation(items)
        } else {
            // Many-match cap: fall back to the top-ranked candidate (last-played-aware).
            return .fallbackBest(items[0])
        }
    }

    /// Delegates to the shared resolver so the extension and the in-app
    /// `application(_:handle:)` path rank a spoken request identically.
    func resolveCandidates(
        mediaName: String,
        audios: [AudioModel],
        lastPlayedURL: URL?
    ) -> [AudioModel] {
        let candidates = MediaSearchResolver.candidates(
            mediaName: mediaName,
            audios: audios,
            lastPlayedURL: lastPlayedURL
        )
        os_log("decide candidates=%{public}d", log: log, type: .info, candidates.count)
        return candidates
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
        // Note: SiriKit Media (INPlayMediaIntent) does not support custom Response
        // templates via .intentdefinition — that surface is for custom INIntent
        // subclasses only. The system speaks its canned dialog for
        // `.failureUnknownMediaType`; no in-app input echo (e.g. "No audiobook
        // matches 'Harry Plotter'") is achievable on this path. Matches Spotify /
        // YouTube Music / Audible behavior.
        if launchState.isUnavailable() {
            completion(INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil))
            return
        }

        // Defense-in-depth: per SiriKit lifecycle, when resolveMediaItems returns
        // all-unsupported, Siri typically speaks its failure dialog directly and
        // does NOT call handle. This branch covers the rare path where handle is
        // invoked with empty mediaItems.
        if intent.mediaItems?.isEmpty ?? true {
            completion(INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil))
            return
        }

        completion(INPlayMediaIntentResponse(code: .handleInApp, userActivity: nil))
    }
}
