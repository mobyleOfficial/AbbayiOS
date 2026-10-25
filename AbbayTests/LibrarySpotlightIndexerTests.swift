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
    private(set) var identifiers: Set<String> = []
    private(set) var calls: [String] = []
    var clearError: Error?
    /// When true, each clear and index waits in `pending` until `releaseNext()`.
    var holdsCompletions = false
    private var pending: [() -> Void] = []

    init(holding identifiers: Set<String> = []) {
        self.identifiers = identifiers
    }

    var pendingCount: Int { pending.count }

    func makeIndexer(log: SiriLogSink = RecordingSiriLogSink()) -> LibrarySpotlightIndexer {
        LibrarySpotlightIndexer(
            clearItems: { [self] done in
                calls.append("clear")
                run { [self] in
                    // A failed clear leaves the items where they were.
                    if clearError == nil { identifiers.removeAll() }
                    done(clearError)
                }
            },
            indexItems: { [self] items, done in
                calls.append("index \(items.map(\.uniqueIdentifier).sorted())")
                run { [self] in
                    identifiers.formUnion(items.map(\.uniqueIdentifier))
                    done(nil)
                }
            },
            log: log
        )
    }

    func releaseNext() {
        guard !pending.isEmpty else { return XCTFail("nothing is waiting") }
        pending.removeFirst()()
    }

    private func run(_ work: @escaping () -> Void) {
        if holdsCompletions { pending.append(work) } else { work() }
    }
}

/// #195: the library's Spotlight index mirrors the library. Each publish clears the library's
/// domain and indexes the books it was given, so deleted books and identifiers no longer in use
/// leave Spotlight.
final class LibrarySpotlightIndexerTests: XCTestCase {
    private func book(_ title: String, _ url: String) -> AudioModel {
        var model = AudioModel()
        model.title = title
        model.url = URL(string: url)
        return model
    }

    func test_publish_afterADelete_theDeletedBookLeavesTheIndex() {
        let index = FakeSpotlightIndex()
        let indexer = index.makeIndexer()

        indexer.index(audios: [book("Dune", "file:///dune.m4b"), book("Emma", "file:///emma.m4b")]) {}
        indexer.index(audios: [book("Emma", "file:///emma.m4b")]) {}

        XCTAssertEqual(index.identifiers, ["file:///emma.m4b"])
    }

    /// Before #186 a moved book was indexed under the URL its bookmark resolved to. That item is
    /// gone after the next publish, which indexes the book under its row's URL only.
    func test_publish_dropsAMovedBooksItemUnderItsOldResolvedURL() {
        let index = FakeSpotlightIndex(holding: ["file:///moved/book.m4b", "file:///book.m4b"])

        index.makeIndexer().index(audios: [book("Book", "file:///book.m4b")]) {}

        XCTAssertEqual(index.identifiers, ["file:///book.m4b"])
    }

    func test_publish_clearsBeforeIndexing() {
        let index = FakeSpotlightIndex()

        index.makeIndexer().index(audios: [book("Dune", "file:///dune.m4b")]) {}

        XCTAssertEqual(index.calls, ["clear", "index [\"file:///dune.m4b\"]"])
    }

    func test_publish_ofAnEmptyLibrary_emptiesTheIndex() {
        let index = FakeSpotlightIndex(holding: ["file:///last.m4b"])
        var completed = false

        index.makeIndexer().index(audios: []) { completed = true }

        XCTAssertTrue(completed)
        XCTAssertEqual(index.identifiers, [])
        XCTAssertEqual(index.calls, ["clear"])
    }

    /// A failed clear is logged by domain and code, and the books are indexed anyway.
    func test_aFailedClear_isLogged_andTheBooksAreStillIndexed() {
        let index = FakeSpotlightIndex()
        index.clearError = NSError(domain: "CSIndexErrorDomain", code: -1003)
        let log = RecordingSiriLogSink()
        var completed = false

        index.makeIndexer(log: log).index(audios: [book("Dune", "file:///dune.m4b")]) { completed = true }

        XCTAssertTrue(completed)
        XCTAssertTrue(index.identifiers.contains("file:///dune.m4b"))
        XCTAssertEqual(log.events, [.spotlightClearingFailed(domain: "CSIndexErrorDomain", code: -1003)])
    }

    /// Publishes that overlap don't interleave (a clear landing after another publish's index would
    /// empty the index): the second waits, a third supersedes it, and every caller completes once
    /// the latest library is indexed.
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
            "clear", "index [\"file:///c.m4b\"]"
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

        XCTAssertEqual(index.calls.last, "clear")
        XCTAssertEqual(index.pendingCount, 1)
    }

    func test_items_carryTheLibrarysDomainIdentifier() throws {
        let item = try XCTUnwrap(LibrarySpotlightIndexer.searchableItem(for: book("Dune", "file:///dune.m4b")))

        XCTAssertEqual(item.domainIdentifier, LibrarySpotlightIndexer.domainIdentifier)
    }
}
