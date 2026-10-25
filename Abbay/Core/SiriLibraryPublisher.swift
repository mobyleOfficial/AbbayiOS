//
//  SiriLibraryPublisher.swift
//  Abbay
//

import AppIntents
import Foundation
import Intents

/// Pushes the current library to every Siri surface that has to know about it.
///
/// Three separate registrations have to stay in step with the library, and all
/// three are silent when missing — the app simply never gets the request:
///
/// * `INVocabulary` teaches Siri the user's own audiobook titles, which is how
///   `INMediaSearch.mediaName` comes back with a usable title instead of a
///   mis-transcription.
/// * `updateAppShortcutParameters()` re-expands the spoken phrases that embed an
///   `AudiobookEntity`. Apple's docs are explicit that entity-parameter phrases do
///   not work at all until the system has fetched entities once, including on
///   first launch.
/// * `INMediaUserContext` reports library size as an app-affinity signal for
///   Siri's media app selection.
/// * Core Spotlight indexing lets the system associate a spoken title with this
///   app while the app is not running.
protocol SiriLibraryPublisherProtocol {
    /// Calls `completion` on the main queue once the publish's asynchronous part (Spotlight
    /// indexing) has finished (#159).
    func publish(audios: [AudioModel], completion: @escaping () -> Void)
}

extension SiriLibraryPublisherProtocol {
    /// For callers that don't wait: library mutations and launch.
    func publish(audios: [AudioModel]) {
        publish(audios: audios) {}
    }
}

final class SiriLibraryPublisher: SiriLibraryPublisherProtocol {
    /// The app's publisher. Not rebindable: `LibrarySnapshotWriter` and `SiriContextRefresher`
    /// take theirs as an init argument, which is where tests inject one (#153).
    static let shared: SiriLibraryPublisherProtocol = SiriLibraryPublisher()

    /// `INVocabulary` replaces the whole set on each call and pays attention to
    /// order, so the list is bounded and most-relevant-first.
    static let vocabularyLimit = 100

    private let mediaUserContextDonor: MediaUserContextDonorProtocol
    private let spotlightIndexer: LibrarySpotlightIndexerProtocol
    private let vocabulary: (NSOrderedSet) -> Void
    private let refreshShortcutParameters: () -> Void
    private let lastPlayed: LastPlayedStore
    private let log: SiriLogSink
    private let diagnostics: SiriDiagnostics
    /// Times the publish for `publish: finished in N ms` (#173).
    private let now: () -> Date

    init(
        mediaUserContextDonor: MediaUserContextDonorProtocol = MediaUserContextDonor.shared,
        spotlightIndexer: LibrarySpotlightIndexerProtocol = LibrarySpotlightIndexer.shared,
        vocabulary: @escaping (NSOrderedSet) -> Void = { strings in
            INVocabulary.shared().setVocabularyStrings(strings, of: .mediaAudiobookTitle)
        },
        refreshShortcutParameters: @escaping () -> Void = {
            AbbayAppShortcuts.updateAppShortcutParameters()
        },
        lastPlayed: LastPlayedStore = .shared,
        log: SiriLogSink = OSSiriLogSink(),
        diagnostics: SiriDiagnostics = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.now = now
        self.mediaUserContextDonor = mediaUserContextDonor
        self.spotlightIndexer = spotlightIndexer
        self.vocabulary = vocabulary
        self.refreshShortcutParameters = refreshShortcutParameters
        self.lastPlayed = lastPlayed
        self.log = log
        self.diagnostics = diagnostics
    }

    /// Only Spotlight reports completion. `INVocabulary`, `INMediaUserContext.becomeCurrent()` and
    /// `updateAppShortcutParameters()` are synchronous calls with no completion API: whatever
    /// work they hand to the system afterwards can't be waited for.
    func publish(audios: [AudioModel], completion: @escaping () -> Void) {
        let started = now()
        let indexing = DispatchGroup()
        indexing.enter()
        spotlightIndexer.index(audios: audios) { indexing.leave() }
        mediaUserContextDonor.donate(libraryItemCount: audios.count)
        vocabulary(NSOrderedSet(array: orderedTitles(for: audios)))
        diagnostics.record("publish books=\(audios.count) refreshingShortcutParams")
        // The unified-log twin of the diagnostics line (#157). The count only, never titles.
        log.log(.publishStarted(bookCount: audios.count))
        refreshShortcutParameters()
        let log = log
        let now = now
        indexing.notify(queue: .main) {
            let milliseconds = Int((now().timeIntervalSince(started) * 1000).rounded())
            log.log(.publishFinished(milliseconds: milliseconds))
            completion()
        }
    }

    /// Exposed for tests: last-played title first, empty titles dropped, capped.
    func orderedTitles(for audios: [AudioModel]) -> [String] {
        var titles = audios.map(\.title).filter { !$0.isEmpty }
        if let lastPlayed = lastPlayed.lastPlayedURL(),
           let recent = audios.first(where: { $0.url == lastPlayed }),
           let index = titles.firstIndex(of: recent.title) {
            let title = titles.remove(at: index)
            titles.insert(title, at: 0)
        }
        return Array(NSOrderedSet(array: titles).compactMap { $0 as? String }.prefix(Self.vocabularyLimit))
    }
}
