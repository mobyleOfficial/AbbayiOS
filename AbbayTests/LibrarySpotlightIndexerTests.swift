//
//  LibrarySpotlightIndexerTests.swift
//  AbbayTests
//

@testable import Abbay
import CoreSpotlight
import XCTest

/// An in-memory stand-in for the library's `CSSearchableIndex`: what it holds, what it was asked,
/// and optionally completions held back, so overlapping publishes can be ordered by hand.
private final class FakeSpotlightIndex {
    /// Identifier → title, so a re-indexed item's new content is visible.
    private(set) var items: [String: String] = [:]
    private(set) var calls: [String] = []
    var clearError: Error?
    var deleteError: Error?
    /// Fails this many index calls, then succeeds.
    var indexFailures = 0
    /// When true, each call waits in `pending` until `releaseNext()`.
    var holdsCompletions = false
    private var pending: [() -> Void] = []

    init(holding identifiers: Set<String> = []) {
        identifiers.forEach { items[$0] = "" }
    }

    var identifiers: Set<String> { Set(items.keys) }
    var pendingCount: Int { pending.count }

    func makeIndexer(
        store: KeyValueStoring = InMemoryKeyValueStore(),
        log: SiriLogSink = RecordingSiriLogSink()
    ) -> LibrarySpotlightIndexer {
        LibrarySpotlightIndexer(
            clearItems: { [self] done in
                calls.append("clear")
                run { [self] in
                    // A failed clear leaves the items where they were.
                    if clearError == nil { items.removeAll() }
                    done(clearError)
                }
            },
            deleteItems: { [self] identifiers, done in
                calls.append("delete \(identifiers.sorted())")
                run { [self] in
                    if deleteError == nil { identifiers.forEach { items[$0] = nil } }
                    done(deleteError)
                }
            },
            indexItems: { [self] newItems, done in
                calls.append("index \(newItems.map(\.uniqueIdentifier).sorted())")
                run { [self] in
                    guard indexFailures == 0 else {
                        indexFailures -= 1
                        return done(NSError(domain: "CSIndexErrorDomain", code: -1003))
                    }
                    newItems.forEach { items[$0.uniqueIdentifier] = $0.attributeSet.title ?? "" }
                    done(nil)
                }
            },
            store: store,
            log: log
        )
    }

    func releaseNext() {
        guard !pending.isEmpty else { return XCTFail("nothing is waiting") }
        pending.removeFirst()()
    }

    func resetCalls() {
        calls = []
    }

    private func run(_ work: @escaping () -> Void) {
        if holdsCompletions { pending.append(work) } else { work() }
    }
}

/// #195: the library's Spotlight index mirrors the library, so deleted books and identifiers no
/// longer in use leave Spotlight. #173: a publish only touches what changed since the last one,
/// which the indexer remembers in its store; without that record it clears and re-indexes.
final class LibrarySpotlightIndexerTests: XCTestCase {
    private func book(_ title: String, _ url: String, artist: String = "") -> AudioModel {
        var model = AudioModel()
        model.title = title
        model.url = URL(string: url)
        model.artist = artist
        return model
    }

    private let dune = "file:///dune.m4b"
    private let emma = "file:///emma.m4b"

    // MARK: - Mirroring (#195)

    func test_publish_afterADelete_theDeletedBookLeavesTheIndex() {
        let index = FakeSpotlightIndex()
        let indexer = index.makeIndexer()

        indexer.index(audios: [book("Dune", dune), book("Emma", emma)]) {}
        indexer.index(audios: [book("Emma", emma)]) {}

        XCTAssertEqual(index.identifiers, [emma])
    }

    /// Before #186 a moved book was indexed under the URL its bookmark resolved to. With no record
    /// (the first publish after updating), the full rebuild clears that item.
    func test_firstPublish_dropsAMovedBooksItemUnderItsOldResolvedURL() {
        let index = FakeSpotlightIndex(holding: ["file:///moved/book.m4b", "file:///book.m4b"])

        index.makeIndexer().index(audios: [book("Book", "file:///book.m4b")]) {}

        XCTAssertEqual(index.identifiers, ["file:///book.m4b"])
    }

    func test_publish_ofAnEmptyLibrary_emptiesTheIndex() {
        let index = FakeSpotlightIndex(holding: ["file:///last.m4b"])
        var completed = false

        index.makeIndexer().index(audios: []) { completed = true }

        XCTAssertTrue(completed)
        XCTAssertEqual(index.identifiers, [])
        XCTAssertEqual(index.calls, ["clear"])
    }

    // MARK: - Incremental (#173)

    /// No record yet (a fresh install, or the first publish after updating): clear, then index all.
    func test_withoutARecord_clearsAndIndexesEverything_andLogsTheRebuild() {
        let index = FakeSpotlightIndex()
        let log = RecordingSiriLogSink()

        index.makeIndexer(log: log).index(audios: [book("Dune", dune), book("Emma", emma)]) {}

        XCTAssertEqual(index.calls, ["clear", "index [\"\(dune)\", \"\(emma)\"]"])
        XCTAssertEqual(log.events, [.spotlightRebuilt(itemCount: 2, reason: .noRecord)])
    }

    func test_anUnchangedLibrary_makesNoSpotlightCalls() {
        let index = FakeSpotlightIndex()
        let log = RecordingSiriLogSink()
        let indexer = index.makeIndexer(log: log)
        indexer.index(audios: [book("Dune", dune), book("Emma", emma)]) {}
        index.resetCalls()
        var completed = false

        indexer.index(audios: [book("Emma", emma), book("Dune", dune)]) { completed = true }

        XCTAssertTrue(completed)
        XCTAssertEqual(index.calls, [])
        XCTAssertEqual(log.events.last, .spotlightUnchanged(itemCount: 2))
    }

    /// The record outlives the indexer: a new launch's indexer reads it from the same store.
    func test_theRecordPersists_acrossIndexers() {
        let index = FakeSpotlightIndex()
        let store = InMemoryKeyValueStore()
        index.makeIndexer(store: store).index(audios: [book("Dune", dune)]) {}
        index.resetCalls()

        index.makeIndexer(store: store).index(audios: [book("Dune", dune)]) {}

        XCTAssertEqual(index.calls, [])
    }

    func test_anAddedBook_isTheOnlyOneIndexed() {
        let index = FakeSpotlightIndex()
        let log = RecordingSiriLogSink()
        let indexer = index.makeIndexer(log: log)
        indexer.index(audios: [book("Dune", dune)]) {}
        index.resetCalls()

        indexer.index(audios: [book("Dune", dune), book("Emma", emma)]) {}

        XCTAssertEqual(index.calls, ["index [\"\(emma)\"]"])
        XCTAssertEqual(index.identifiers, [dune, emma])
        XCTAssertEqual(log.events.last, .spotlightUpdated(indexed: 1, deleted: 0))
    }

    func test_aRemovedBook_isDeletedByIdentifier_andNothingIsIndexed() {
        let index = FakeSpotlightIndex()
        let log = RecordingSiriLogSink()
        let indexer = index.makeIndexer(log: log)
        indexer.index(audios: [book("Dune", dune), book("Emma", emma)]) {}
        index.resetCalls()

        indexer.index(audios: [book("Emma", emma)]) {}

        XCTAssertEqual(index.calls, ["delete [\"\(dune)\"]"])
        XCTAssertEqual(index.identifiers, [emma])
        XCTAssertEqual(log.events.last, .spotlightUpdated(indexed: 0, deleted: 1))
    }

    func test_aRenamedBook_isReindexed_underItsIdentifier() {
        let index = FakeSpotlightIndex()
        let indexer = index.makeIndexer()
        indexer.index(audios: [book("Dune", dune), book("Emma", emma)]) {}
        index.resetCalls()

        indexer.index(audios: [book("Dune Messiah", dune), book("Emma", emma)]) {}

        XCTAssertEqual(index.calls, ["index [\"\(dune)\"]"])
        XCTAssertEqual(index.items[dune], "Dune Messiah")
    }

    /// Everything the item carries is in the fingerprint, not just the title.
    func test_aChangedAuthor_isReindexed() {
        let index = FakeSpotlightIndex()
        let indexer = index.makeIndexer()
        indexer.index(audios: [book("Dune", dune, artist: "Herbert")]) {}
        index.resetCalls()

        indexer.index(audios: [book("Dune", dune, artist: "Frank Herbert")]) {}

        XCTAssertEqual(index.calls, ["index [\"\(dune)\"]"])
    }

    /// A book that became untitled has no item any more, so it's deleted.
    func test_aBookThatLostItsTitle_isDeleted() {
        let index = FakeSpotlightIndex()
        let indexer = index.makeIndexer()
        indexer.index(audios: [book("Dune", dune)]) {}
        index.resetCalls()

        indexer.index(audios: [book("", dune)]) {}

        XCTAssertEqual(index.calls, ["delete [\"\(dune)\"]"])
    }

    func test_anAddAndARemove_deleteThenIndex() {
        let index = FakeSpotlightIndex()
        let indexer = index.makeIndexer()
        indexer.index(audios: [book("Dune", dune)]) {}
        index.resetCalls()

        indexer.index(audios: [book("Emma", emma)]) {}

        XCTAssertEqual(index.calls, ["delete [\"\(dune)\"]", "index [\"\(emma)\"]"])
        XCTAssertEqual(index.identifiers, [emma])
    }

    /// Two rows with one URL make one item, so the second publish sees no change.
    func test_duplicateIdentifiers_areIndexedOnce() {
        let index = FakeSpotlightIndex()
        let indexer = index.makeIndexer()

        indexer.index(audios: [book("Dune", dune), book("Dune", dune)]) {}
        XCTAssertEqual(index.calls, ["clear", "index [\"\(dune)\"]"])
        index.resetCalls()
        indexer.index(audios: [book("Dune", dune), book("Dune", dune)]) {}

        XCTAssertEqual(index.calls, [])
    }

    func test_anUnreadableRecord_rebuilds() {
        let index = FakeSpotlightIndex()
        let store = InMemoryKeyValueStore([LibrarySpotlightIndexer.recordKey: "not a record"])
        let log = RecordingSiriLogSink()

        index.makeIndexer(store: store, log: log).index(audios: [book("Dune", dune)]) {}

        XCTAssertEqual(index.calls, ["clear", "index [\"\(dune)\"]"])
        XCTAssertEqual(log.events, [.spotlightRebuilt(itemCount: 1, reason: .noRecord)])
    }

    // MARK: - Recovery

    /// A failed delete falls back, once, to the full rebuild, which takes the book out anyway.
    func test_aFailedDelete_isLogged_andFallsBackToAFullRebuild() {
        let index = FakeSpotlightIndex()
        let log = RecordingSiriLogSink()
        let indexer = index.makeIndexer(log: log)
        indexer.index(audios: [book("Dune", dune), book("Emma", emma)]) {}
        index.resetCalls()
        index.deleteError = NSError(domain: "CSIndexErrorDomain", code: -1003)
        var completed = false

        indexer.index(audios: [book("Emma", emma)]) { completed = true }

        XCTAssertTrue(completed)
        XCTAssertEqual(index.calls, ["delete [\"\(dune)\"]", "clear", "index [\"\(emma)\"]"])
        XCTAssertEqual(index.identifiers, [emma])
        XCTAssertEqual(Array(log.events.suffix(2)), [
            .spotlightDeletingFailed(domain: "CSIndexErrorDomain", code: -1003),
            .spotlightRebuilt(itemCount: 1, reason: .afterFailure)
        ])
    }

    func test_aFailedIncrementalIndex_fallsBackToAFullRebuild() {
        let index = FakeSpotlightIndex()
        let log = RecordingSiriLogSink()
        let indexer = index.makeIndexer(log: log)
        indexer.index(audios: [book("Dune", dune)]) {}
        index.resetCalls()
        index.indexFailures = 1

        indexer.index(audios: [book("Dune", dune), book("Emma", emma)]) {}

        XCTAssertEqual(index.calls, [
            "index [\"\(emma)\"]", "clear", "index [\"\(dune)\", \"\(emma)\"]"
        ])
        XCTAssertEqual(index.identifiers, [dune, emma])
        XCTAssertEqual(Array(log.events.suffix(2)), [
            .spotlightIndexingFailed(domain: "CSIndexErrorDomain", code: -1003),
            .spotlightRebuilt(itemCount: 2, reason: .afterFailure)
        ])
    }

    /// The fallback runs once per publish. If it fails too, no record is kept, so the next publish
    /// rebuilds again rather than trusting an index in an unknown state.
    func test_aFailedRebuild_isNotRetried_andTheNextPublishRebuildsAgain() {
        let index = FakeSpotlightIndex()
        let log = RecordingSiriLogSink()
        let indexer = index.makeIndexer(log: log)
        index.indexFailures = 1
        var completed = false

        indexer.index(audios: [book("Dune", dune)]) { completed = true }

        XCTAssertTrue(completed)
        XCTAssertEqual(index.calls, ["clear", "index [\"\(dune)\"]"])
        XCTAssertEqual(log.events, [.spotlightIndexingFailed(domain: "CSIndexErrorDomain", code: -1003)])
        index.resetCalls()

        indexer.index(audios: [book("Dune", dune)]) {}

        XCTAssertEqual(index.calls, ["clear", "index [\"\(dune)\"]"])
        XCTAssertEqual(log.events.last, .spotlightRebuilt(itemCount: 1, reason: .noRecord))
    }

    /// A failed clear is logged by domain and code, and the books are indexed anyway. The index may
    /// still hold old items, so no record is kept and the next publish rebuilds.
    func test_aFailedClear_isLogged_theBooksAreStillIndexed_andTheNextPublishRebuilds() {
        let index = FakeSpotlightIndex()
        index.clearError = NSError(domain: "CSIndexErrorDomain", code: -1003)
        let log = RecordingSiriLogSink()
        let indexer = index.makeIndexer(log: log)
        var completed = false

        indexer.index(audios: [book("Dune", dune)]) { completed = true }

        XCTAssertTrue(completed)
        XCTAssertTrue(index.identifiers.contains(dune))
        XCTAssertEqual(log.events, [.spotlightClearingFailed(domain: "CSIndexErrorDomain", code: -1003)])
        index.clearError = nil
        index.resetCalls()

        indexer.index(audios: [book("Dune", dune)]) {}

        XCTAssertEqual(index.calls, ["clear", "index [\"\(dune)\"]"])
    }

    // MARK: - One at a time (#195)

    /// Publishes that overlap don't interleave: the second waits, a third supersedes it, and every
    /// caller completes once the latest library is indexed.
    func test_overlappingPublishes_runOneAtATime_andEndWithTheLatestLibrary() {
        let index = FakeSpotlightIndex()
        index.holdsCompletions = true
        let indexer = index.makeIndexer()
        var completed: [Int] = []

        indexer.index(audios: [book("A", "file:///a.m4b"), book("B", "file:///b.m4b")]) { completed.append(1) }
        indexer.index(audios: [book("A", "file:///a.m4b")]) { completed.append(2) }
        indexer.index(audios: [book("C", "file:///c.m4b")]) { completed.append(3) }
        XCTAssertEqual(index.calls, ["clear"], "the later publishes wait for the first")

        while index.pendingCount > 0 { index.releaseNext() }

        XCTAssertEqual(index.calls, [
            "clear", "index [\"file:///a.m4b\", \"file:///b.m4b\"]",
            "delete [\"file:///a.m4b\", \"file:///b.m4b\"]", "index [\"file:///c.m4b\"]"
        ])
        XCTAssertEqual(index.identifiers, ["file:///c.m4b"])
        XCTAssertEqual(completed, [1, 2, 3])
    }

    /// Once a run of publishes has finished, the next one starts straight away.
    func test_aPublishAfterTheLastOneFinished_runsAtOnce() {
        let index = FakeSpotlightIndex()
        let indexer = index.makeIndexer()
        indexer.index(audios: [book("A", "file:///a.m4b")]) {}
        index.holdsCompletions = true

        indexer.index(audios: [book("B", "file:///b.m4b")]) {}

        XCTAssertEqual(index.calls.last, "delete [\"file:///a.m4b\"]")
        XCTAssertEqual(index.pendingCount, 1)
    }

    // MARK: - Items

    func test_items_carryTheLibrarysDomainIdentifier() throws {
        let item = try XCTUnwrap(LibrarySpotlightIndexer.searchableItem(for: book("Dune", dune)))

        XCTAssertEqual(item.domainIdentifier, LibrarySpotlightIndexer.domainIdentifier)
    }

    func test_fingerprint_isStable_andCoversEveryField() throws {
        let base = try XCTUnwrap(SpotlightItemContent(audio: book("Dune", dune, artist: "Herbert")))
        let same = try XCTUnwrap(SpotlightItemContent(audio: book("Dune", dune, artist: "Herbert")))
        var otherAlbum = book("Dune", dune, artist: "Herbert")
        otherAlbum.albumName = "Saga"

        XCTAssertEqual(base.fingerprint, same.fingerprint)
        XCTAssertEqual(base.fingerprint.count, 64, "a SHA-256 in hex")
        XCTAssertNotEqual(base.fingerprint, try XCTUnwrap(SpotlightItemContent(audio: otherAlbum)).fingerprint)
        XCTAssertFalse(base.fingerprint.contains("Dune"), "the record holds no titles")
    }
}
