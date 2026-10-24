//
//  LibrarySpotlightIndexer.swift
//  Abbay
//

import CoreServices
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Indexes the library in Core Spotlight as audio items.
///
/// Apple lists this alongside `INVocabulary` and `INMediaUserContext` as a way to
/// improve Siri media matching and app selection: it lets the system associate a
/// spoken title with this app even when the app is not running. Items are stored
/// with `completeUntilFirstUserAuthentication` protection for that reason.
protocol LibrarySpotlightIndexerProtocol {
    /// Calls `completion` once the index has taken the items, or failed to (logged), on any
    /// queue. Immediately when there is nothing to index.
    func index(audios: [AudioModel], completion: @escaping () -> Void)
}

final class LibrarySpotlightIndexer: LibrarySpotlightIndexerProtocol {
    // `var` so tests can rebind.
    static var shared: LibrarySpotlightIndexerProtocol = LibrarySpotlightIndexer()

    /// Indexes the items and calls back with the index's outcome.
    private let indexItems: ([CSSearchableItem], @escaping (Error?) -> Void) -> Void

    /// A named index with `completeUntilFirstUserAuthentication` protection, so the
    /// system can still read these items while the device is locked.
    private static let index = CSSearchableIndex(
        name: "com.edyuto.Abbay.library",
        protectionClass: .completeUntilFirstUserAuthentication
    )

    init(
        indexItems: @escaping ([CSSearchableItem], @escaping (Error?) -> Void) -> Void = { items, done in
            LibrarySpotlightIndexer.index.indexSearchableItems(items, completionHandler: done)
        }
    ) {
        self.indexItems = indexItems
    }

    func index(audios: [AudioModel], completion: @escaping () -> Void) {
        let items = audios.compactMap(Self.searchableItem(for:))
        guard !items.isEmpty else {
            completion()
            return
        }
        indexItems(items) { error in
            if let error = error as NSError? {
                Log.siri.error(
                    "spotlight indexing failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)"
                )
            }
            completion()
        }
    }

    /// Exposed for tests.
    static func searchableItem(for audio: AudioModel) -> CSSearchableItem? {
        guard let url = audio.url, !audio.title.isEmpty else { return nil }
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.audio)
        attributes.title = audio.title
        attributes.displayName = audio.title
        if !audio.artist.isEmpty {
            attributes.artist = audio.artist
        }
        if !audio.albumName.isEmpty {
            attributes.album = audio.albumName
        }
        let item = CSSearchableItem(
            uniqueIdentifier: url.absoluteString,
            domainIdentifier: "com.edyuto.Abbay.library",
            attributeSet: attributes
        )
        return item
    }
}
