//
//  SpotlightReindexDelegateTests.swift
//  AbbayTests
//

@testable import Abbay
import CoreSpotlight
import XCTest

private final class SpyIndexer: LibrarySpotlightIndexerProtocol {
    var forgotten: [[String]?] = []

    func index(audios: [AudioModel], completion: @escaping () -> Void) { completion() }

    func forgetIndexedItems(_ identifiers: [String]?) {
        forgotten.append(identifiers)
    }
}

/// #205: the system's re-index requests forget the items in the indexer's record and publish, and
/// are acknowledged once the publish has finished.
final class SpotlightReindexDelegateTests: XCTestCase {
    private let index = CSSearchableIndex(name: "com.edyuto.Abbay.tests.reindex")
    private var indexer = SpyIndexer()
    private var log = RecordingSiriLogSink()
    /// Each publish's completion, held until the test runs it.
    private var publishes: [() -> Void] = []

    override func setUp() {
        super.setUp()
        indexer = SpyIndexer()
        log = RecordingSiriLogSink()
        publishes = []
    }

    private func makeDelegate() -> SpotlightReindexDelegate {
        SpotlightReindexDelegate(indexer: indexer, publish: { [self] done in publishes.append(done) }, log: log)
    }

    func test_reindexAll_forgetsEverything_publishes_andAcknowledgesAfterThePublish() {
        var acknowledged = false

        let delegate = makeDelegate()
        delegate.searchableIndex(index, reindexAllSearchableItemsWithAcknowledgementHandler: { acknowledged = true })

        XCTAssertEqual(indexer.forgotten.count, 1)
        XCTAssertNil(indexer.forgotten.first ?? ["not nil"])
        XCTAssertEqual(publishes.count, 1)
        XCTAssertFalse(acknowledged, "not before the publish has finished")
        publishes[0]()
        XCTAssertTrue(acknowledged)
        XCTAssertEqual(log.events, [.spotlightReindexRequested(itemCount: nil)])
    }

    func test_reindexSome_forgetsThoseItems_andPublishes() {
        var acknowledged = false

        makeDelegate().searchableIndex(
            index,
            reindexSearchableItemsWithIdentifiers: ["file:///dune.m4b", "file:///emma.m4b"],
            acknowledgementHandler: { acknowledged = true }
        )

        XCTAssertEqual(indexer.forgotten, [["file:///dune.m4b", "file:///emma.m4b"]])
        XCTAssertEqual(publishes.count, 1)
        publishes[0]()
        XCTAssertTrue(acknowledged)
        XCTAssertEqual(log.events, [.spotlightReindexRequested(itemCount: 2)])
    }

    /// End to end with the real indexer over a fake index: a lost index comes back.
    func test_withTheRealIndexer_aRequestRebuildsTheLostIndex() {
        var items = Set<String>()
        let realIndexer = LibrarySpotlightIndexer(
            clearItems: { done in items.removeAll(); done(nil) },
            deleteItems: { identifiers, done in items.subtract(identifiers); done(nil) },
            indexItems: { newItems, done in items.formUnion(newItems.map(\.uniqueIdentifier)); done(nil) },
            store: InMemoryKeyValueStore(),
            log: RecordingSiriLogSink()
        )
        var book = AudioModel()
        book.title = "Dune"
        book.url = URL(string: "file:///dune.m4b")
        realIndexer.index(audios: [book]) {}
        items.removeAll()
        let delegate = SpotlightReindexDelegate(
            indexer: realIndexer,
            publish: { done in realIndexer.index(audios: [book], completion: done) },
            log: log
        )
        var acknowledged = false

        delegate.searchableIndex(index, reindexAllSearchableItemsWithAcknowledgementHandler: { acknowledged = true })

        XCTAssertEqual(items, ["file:///dune.m4b"])
        XCTAssertTrue(acknowledged)
    }
}
