//
//  SpotlightReindexDelegate.swift
//  Abbay
//

import CoreSpotlight
import Foundation

/// Answers the system's requests to re-index the library's Spotlight items (#205).
///
/// The indexer trusts its record of what the index holds (#173), so after the system loses the
/// items (Spotlight's own index reset, a backup restore that keeps `UserDefaults`) no publish
/// would put them back. When the system notices, it asks the index's delegate for them again.
/// This forgets them in the record and publishes the library, which then rebuilds the index (all
/// items) or indexes the named ones as additions; the system is acknowledged once that publish
/// has finished.
///
/// Attached to the app's named index at launch (`AppDelegate`). The requests reach it while the
/// app runs; a request made while it doesn't would need a Core Spotlight index extension, which
/// Abbay doesn't have (#218).
final class SpotlightReindexDelegate: NSObject, CSSearchableIndexDelegate {
    private let indexer: LibrarySpotlightIndexerProtocol
    /// Publishes the library and calls back once the publish has finished.
    private let publish: (@escaping () -> Void) -> Void
    private let log: SiriLogSink

    init(
        indexer: LibrarySpotlightIndexerProtocol = LibrarySpotlightIndexer.shared,
        publish: @escaping (@escaping () -> Void) -> Void,
        log: SiriLogSink = OSSiriLogSink()
    ) {
        self.indexer = indexer
        self.publish = publish
        self.log = log
    }

    func searchableIndex(
        _ searchableIndex: CSSearchableIndex,
        reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void
    ) {
        log.log(.spotlightReindexRequested(itemCount: nil))
        indexer.forgetIndexedItems(nil)
        publish(acknowledgementHandler)
    }

    func searchableIndex(
        _ searchableIndex: CSSearchableIndex,
        reindexSearchableItemsWithIdentifiers identifiers: [String],
        acknowledgementHandler: @escaping () -> Void
    ) {
        log.log(.spotlightReindexRequested(itemCount: identifiers.count))
        indexer.forgetIndexedItems(identifiers)
        publish(acknowledgementHandler)
    }
}
