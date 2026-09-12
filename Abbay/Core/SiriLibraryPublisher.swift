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
protocol SiriLibraryPublisherProtocol {
    func publish(audios: [AudioModel])
}

final class SiriLibraryPublisher: SiriLibraryPublisherProtocol {
    /// `var` so tests can rebind.
    static var shared: SiriLibraryPublisherProtocol = SiriLibraryPublisher()

    /// `INVocabulary` replaces the whole set on each call and pays attention to
    /// order, so the list is bounded and most-relevant-first.
    static let vocabularyLimit = 100

    private let mediaUserContextDonor: MediaUserContextDonorProtocol
    private let vocabulary: (NSOrderedSet) -> Void
    private let refreshShortcutParameters: () -> Void

    init(
        mediaUserContextDonor: MediaUserContextDonorProtocol = MediaUserContextDonor.shared,
        vocabulary: @escaping (NSOrderedSet) -> Void = { strings in
            INVocabulary.shared().setVocabularyStrings(strings, of: .mediaAudiobookTitle)
        },
        refreshShortcutParameters: @escaping () -> Void = {
            AbbayAppShortcuts.updateAppShortcutParameters()
        }
    ) {
        self.mediaUserContextDonor = mediaUserContextDonor
        self.vocabulary = vocabulary
        self.refreshShortcutParameters = refreshShortcutParameters
    }

    func publish(audios: [AudioModel]) {
        mediaUserContextDonor.donate(libraryItemCount: audios.count)
        vocabulary(NSOrderedSet(array: orderedTitles(for: audios)))
        refreshShortcutParameters()
    }

    /// Exposed for tests: last-played title first, empty titles dropped, capped.
    func orderedTitles(for audios: [AudioModel]) -> [String] {
        var titles = audios.map(\.title).filter { !$0.isEmpty }
        if let lastPlayed = LastPlayedStore.lastPlayedURL(),
           let recent = audios.first(where: { $0.url == lastPlayed }),
           let index = titles.firstIndex(of: recent.title) {
            let title = titles.remove(at: index)
            titles.insert(title, at: 0)
        }
        return Array(NSOrderedSet(array: titles).compactMap { $0 as? String }.prefix(Self.vocabularyLimit))
    }
}
