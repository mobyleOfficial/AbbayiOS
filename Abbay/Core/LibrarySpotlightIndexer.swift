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
///
/// The index mirrors the library (#195): each publish clears every item under the library's domain
/// identifier, then indexes the books it was given. So a deleted book leaves Spotlight at the next
/// publish, and so do items under identifiers the app no longer uses (a moved book's resolved URL,
/// which was its id before #186).
protocol LibrarySpotlightIndexerProtocol {
    /// Replaces the index's items with `audios`' and calls `completion` once the index has taken
    /// them, or failed to (logged), on any queue.
    func index(audios: [AudioModel], completion: @escaping () -> Void)
}

final class LibrarySpotlightIndexer: LibrarySpotlightIndexerProtocol {
    // `var` so tests can rebind.
    static var shared: LibrarySpotlightIndexerProtocol = LibrarySpotlightIndexer()

    /// Every item's domain identifier, which is what clearing deletes by.
    static let domainIdentifier = "com.edyuto.Abbay.library"

    /// Deletes every item under `domainIdentifier` and calls back with the index's outcome.
    private let clearItems: (@escaping (Error?) -> Void) -> Void
    /// Indexes the items and calls back with the index's outcome.
    private let indexItems: ([CSSearchableItem], @escaping (Error?) -> Void) -> Void
    private let log: SiriLogSink

    /// Publishes can overlap (a delete right after an import), and a clear from one landing after
    /// another's index would empty the index. So one replacement runs at a time; one asked for
    /// meanwhile waits, and a newer one supersedes it: only the latest library is indexed, and
    /// every waiting caller's completion runs when it is.
    private let lock = NSLock()
    private var isReplacing = false
    private var waiting: (items: [CSSearchableItem], completions: [() -> Void])?

    /// A named index with `completeUntilFirstUserAuthentication` protection, so the
    /// system can still read these items while the device is locked.
    private static let index = CSSearchableIndex(
        name: "com.edyuto.Abbay.library",
        protectionClass: .completeUntilFirstUserAuthentication
    )

    init(
        clearItems: @escaping (@escaping (Error?) -> Void) -> Void = { done in
            LibrarySpotlightIndexer.index.deleteSearchableItems(
                withDomainIdentifiers: [LibrarySpotlightIndexer.domainIdentifier],
                completionHandler: done
            )
        },
        indexItems: @escaping ([CSSearchableItem], @escaping (Error?) -> Void) -> Void = { items, done in
            LibrarySpotlightIndexer.index.indexSearchableItems(items, completionHandler: done)
        },
        log: SiriLogSink = OSSiriLogSink()
    ) {
        self.clearItems = clearItems
        self.indexItems = indexItems
        self.log = log
    }

    /// An empty library still clears: the last book's delete must take its item with it.
    func index(audios: [AudioModel], completion: @escaping () -> Void) {
        let items = audios.compactMap(Self.searchableItem(for:))
        lock.lock()
        guard !isReplacing else {
            waiting = (items, (waiting?.completions ?? []) + [completion])
            lock.unlock()
            return
        }
        isReplacing = true
        lock.unlock()
        replace(with: items, completions: [completion])
    }

    private func replace(with items: [CSSearchableItem], completions: [() -> Void]) {
        let log = log
        clearItems { [self] error in
            if let error = error as NSError? {
                log.log(.spotlightClearingFailed(error))
            }
            // Indexed even when clearing failed: the library's books are still worth finding.
            guard !items.isEmpty else {
                finish(completions)
                return
            }
            indexItems(items) { [self] error in
                if let error = error as NSError? {
                    log.log(.spotlightIndexingFailed(error))
                }
                finish(completions)
            }
        }
    }

    private func finish(_ completions: [() -> Void]) {
        completions.forEach { $0() }
        lock.lock()
        guard let next = waiting else {
            isReplacing = false
            lock.unlock()
            return
        }
        waiting = nil
        lock.unlock()
        replace(with: next.items, completions: next.completions)
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
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
        return item
    }
}
