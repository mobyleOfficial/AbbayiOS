//
//  LibrarySpotlightIndexer.swift
//  Abbay
//

import CoreServices
import CoreSpotlight
import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Indexes the library in Core Spotlight as audio items.
///
/// Apple lists this alongside `INVocabulary` and `INMediaUserContext` as a way to
/// improve Siri media matching and app selection: it lets the system associate a
/// spoken title with this app even when the app is not running. Items are stored
/// with `completeUntilFirstUserAuthentication` protection for that reason.
///
/// The index mirrors the library (#195): a deleted book leaves Spotlight at the next publish, and
/// so do items under identifiers the app no longer uses (a moved book's resolved URL, which was its
/// id before #186).
///
/// Each publish only touches what changed (#173). The indexer keeps a record of what the index
/// holds (each item's identifier and a fingerprint of its content) in its store, and compares the
/// library with it: items that left the library or no longer have an item are deleted by
/// identifier, new and changed ones are indexed, and an unchanged library makes no Core Spotlight
/// call at all. Without a record (a fresh install, the first publish after updating, or after a
/// failure) the publish clears the whole domain and indexes every book, as every publish did before.
///
/// The record can outlive the index: Spotlight's own index reset, or a backup restore that brings
/// back `UserDefaults` without it. The system then asks for the items again through the index's
/// `CSSearchableIndexDelegate` (`SpotlightReindexDelegate`, #205), which forgets them
/// (`forgetIndexedItems`) and publishes.
protocol LibrarySpotlightIndexerProtocol {
    /// Makes the index's items `audios`' and calls `completion` once the index has taken them, or
    /// failed to (logged), on any queue.
    func index(audios: [AudioModel], completion: @escaping () -> Void)

    /// The index no longer holds these items (nil: any of the app's), whatever the record says: the
    /// next update indexes them again, every book by a rebuild for nil, else these as additions.
    /// Applied when the next update starts, so an update in flight can't save its record over it.
    func forgetIndexedItems(_ identifiers: [String]?)
}

/// Everything one book's Spotlight item carries. The item is built from this and nothing else, so
/// its fingerprint covers whatever the item shows: add a field to the item here, and every book is
/// re-indexed once because the fingerprints change.
struct SpotlightItemContent: Codable, Equatable {
    let identifier: String
    let title: String
    let artist: String
    let album: String

    /// Nil for a book Spotlight can't show: no URL or no title.
    init?(audio: AudioModel) {
        guard let url = audio.url, !audio.title.isEmpty else { return nil }
        identifier = url.absoluteString
        title = audio.title
        artist = audio.artist
        album = audio.albumName
    }

    /// SHA-256, in hex, of the content's JSON with sorted keys: stable across launches, and the
    /// record keeps no titles.
    var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(self)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    var searchableItem: CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.audio)
        attributes.title = title
        attributes.displayName = title
        if !artist.isEmpty {
            attributes.artist = artist
        }
        if !album.isEmpty {
            attributes.album = album
        }
        return CSSearchableItem(
            uniqueIdentifier: identifier,
            domainIdentifier: LibrarySpotlightIndexer.domainIdentifier,
            attributeSet: attributes
        )
    }
}

final class LibrarySpotlightIndexer: LibrarySpotlightIndexerProtocol {
    // `var` so tests can rebind.
    static var shared: LibrarySpotlightIndexerProtocol = LibrarySpotlightIndexer()

    /// Every item's domain identifier, which is what clearing deletes by.
    static let domainIdentifier = "com.edyuto.Abbay.library"

    /// What the index holds after the last successful publish: `[identifier: fingerprint]`. Absent
    /// while the index's state is unknown, which makes the next publish rebuild.
    static let recordKey = "abbay.spotlightIndexRecord.v1"

    /// Deletes every item under `domainIdentifier` and calls back with the index's outcome.
    private let clearItems: (@escaping (Error?) -> Void) -> Void
    /// Deletes the items with these identifiers and calls back with the index's outcome.
    private let deleteItems: ([String], @escaping (Error?) -> Void) -> Void
    /// Indexes the items and calls back with the index's outcome.
    private let indexItems: ([CSSearchableItem], @escaping (Error?) -> Void) -> Void
    private let store: KeyValueStoring
    private let log: SiriLogSink

    /// Publishes can overlap (a delete right after an import), and a clear from one landing after
    /// another's index would empty the index; two diffs against one record would also race. So one
    /// update runs at a time; one asked for meanwhile waits, and a newer one supersedes it: only the
    /// latest library is indexed, and every waiting caller's completion runs when it is.
    private let lock = NSLock()
    private var isUpdating = false
    private var waiting: (contents: [SpotlightItemContent], completions: [() -> Void])?
    /// What `forgetIndexedItems` asked for, until the next update drops it from the record.
    private var forgotten: Forgotten?

    private enum Forgotten {
        case all
        case only(Set<String>)
    }

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
        deleteItems: @escaping ([String], @escaping (Error?) -> Void) -> Void = { identifiers, done in
            LibrarySpotlightIndexer.index.deleteSearchableItems(withIdentifiers: identifiers, completionHandler: done)
        },
        indexItems: @escaping ([CSSearchableItem], @escaping (Error?) -> Void) -> Void = { items, done in
            LibrarySpotlightIndexer.index.indexSearchableItems(items, completionHandler: done)
        },
        store: KeyValueStoring = LocalStorage.preferences,
        log: SiriLogSink = OSSiriLogSink()
    ) {
        self.clearItems = clearItems
        self.deleteItems = deleteItems
        self.indexItems = indexItems
        self.store = store
        self.log = log
    }

    func index(audios: [AudioModel], completion: @escaping () -> Void) {
        let contents = Self.uniqueContents(of: audios)
        lock.lock()
        guard !isUpdating else {
            waiting = (contents, (waiting?.completions ?? []) + [completion])
            lock.unlock()
            return
        }
        isUpdating = true
        lock.unlock()
        update(to: contents, completions: [completion])
    }

    func forgetIndexedItems(_ identifiers: [String]?) {
        lock.lock()
        defer { lock.unlock() }
        switch (forgotten, identifiers) {
        case (.all?, _), (_, nil):
            forgotten = .all
        case let (.only(known)?, identifiers?):
            forgotten = .only(known.union(identifiers))
        case let (nil, identifiers?):
            forgotten = .only(Set(identifiers))
        }
    }

    /// Sets the delegate of the index the app writes to (held weakly), so the system's re-index
    /// requests reach it (#205).
    static func attach(_ delegate: CSSearchableIndexDelegate) {
        index.indexDelegate = delegate
    }

    /// Exposed for tests.
    static func searchableItem(for audio: AudioModel) -> CSSearchableItem? {
        SpotlightItemContent(audio: audio)?.searchableItem
    }

    // MARK: - Updating

    /// One item per identifier, in library order: two rows under one URL are one Spotlight item.
    private static func uniqueContents(of audios: [AudioModel]) -> [SpotlightItemContent] {
        var seen = Set<String>()
        return audios.compactMap(SpotlightItemContent.init(audio:)).filter { seen.insert($0.identifier).inserted }
    }

    private func update(to contents: [SpotlightItemContent], completions: [() -> Void]) {
        lock.lock()
        let forgotten = forgotten
        self.forgotten = nil
        lock.unlock()
        if case .all? = forgotten {
            return rebuild(with: contents, reason: .reindexRequested, completions: completions)
        }
        guard var record = loadRecord() else {
            rebuild(with: contents, reason: .noRecord, completions: completions)
            return
        }
        if case let .only(identifiers)? = forgotten {
            identifiers.forEach { record[$0] = nil }
        }
        let wanted = Dictionary(uniqueKeysWithValues: contents.map { ($0.identifier, $0.fingerprint) })
        let deletions = record.keys.filter { wanted[$0] == nil }.sorted()
        let additions = contents.filter { record[$0.identifier] != wanted[$0.identifier] }
        guard !deletions.isEmpty || !additions.isEmpty else {
            log.log(.spotlightUnchanged(itemCount: contents.count))
            finish(completions)
            return
        }
        let log = log
        // The fallback: the index may now hold part of the change, so it is rebuilt from scratch.
        let recover = { [self] in rebuild(with: contents, reason: .afterFailure, completions: completions) }
        delete(deletions) { [self] error in
            if let error {
                log.log(.spotlightDeletingFailed(error))
                return recover()
            }
            index(additions) { [self] error in
                if let error {
                    log.log(.spotlightIndexingFailed(error))
                    return recover()
                }
                saveRecord(wanted)
                log.log(.spotlightUpdated(indexed: additions.count, deleted: deletions.count))
                finish(completions)
            }
        }
    }

    /// Clears the domain and indexes every book: what each publish did before #173. Runs once per
    /// publish. The record is dropped first, so if the app dies halfway, or this fails, the next
    /// publish rebuilds again rather than trusting an index in an unknown state.
    private func rebuild(with contents: [SpotlightItemContent], reason: SpotlightRebuildReason, completions: [() -> Void]) {
        store.removeObject(forKey: Self.recordKey)
        let log = log
        clearItems { [self] error in
            let clearError = error as NSError?
            if let clearError {
                log.log(.spotlightClearingFailed(clearError))
            }
            // Indexed even when clearing failed: the library's books are still worth finding.
            index(contents) { [self] error in
                if let error {
                    log.log(.spotlightIndexingFailed(error))
                } else if clearError == nil {
                    saveRecord(Dictionary(uniqueKeysWithValues: contents.map { ($0.identifier, $0.fingerprint) }))
                    log.log(.spotlightRebuilt(itemCount: contents.count, reason: reason))
                }
                finish(completions)
            }
        }
    }

    /// No call for nothing to delete.
    private func delete(_ identifiers: [String], done: @escaping (NSError?) -> Void) {
        guard !identifiers.isEmpty else { return done(nil) }
        deleteItems(identifiers) { done($0 as NSError?) }
    }

    /// No call for nothing to index.
    private func index(_ contents: [SpotlightItemContent], done: @escaping (NSError?) -> Void) {
        guard !contents.isEmpty else { return done(nil) }
        indexItems(contents.map(\.searchableItem)) { done($0 as NSError?) }
    }

    private func loadRecord() -> [String: String]? {
        store.object(forKey: Self.recordKey) as? [String: String]
    }

    private func saveRecord(_ record: [String: String]) {
        store.set(record, forKey: Self.recordKey)
    }

    private func finish(_ completions: [() -> Void]) {
        completions.forEach { $0() }
        lock.lock()
        guard let next = waiting else {
            isUpdating = false
            lock.unlock()
            return
        }
        waiting = nil
        lock.unlock()
        update(to: next.contents, completions: next.completions)
    }
}
