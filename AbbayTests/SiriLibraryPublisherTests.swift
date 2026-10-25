//
//  SiriLibraryPublisherTests.swift
//  AbbayTests
//

@testable import Abbay
import Foundation
import Intents
import XCTest

private final class SpyMediaUserContextDonor: MediaUserContextDonorProtocol {
    var donatedCounts = [Int]()

    func donate(libraryItemCount: Int) {
        donatedCounts.append(libraryItemCount)
    }
}

private final class SpySpotlightIndexer: LibrarySpotlightIndexerProtocol {
    var indexedTitles = [[String]]()
    /// When false, the indexing completion waits in `pendingCompletion`.
    var completesImmediately = true
    var pendingCompletion: (() -> Void)?

    func index(audios: [AudioModel], completion: @escaping () -> Void) {
        indexedTitles.append(audios.map(\.title))
        if completesImmediately { completion() } else { pendingCompletion = completion }
    }
}

private final class SpySiriLibraryPublisher: SiriLibraryPublisherProtocol {
    var publishedTitles = [[String]]()

    func publish(audios: [AudioModel], completion: @escaping () -> Void) {
        publishedTitles.append(audios.map(\.title))
        completion()
    }
}

final class SiriLibraryPublisherTests: XCTestCase {
    /// The last-played pointer the publisher orders by, fresh per test.
    private let lastPlayed = LastPlayedStore.inMemory()

    /// Each test's diagnostics trail, so a publish never writes the real App Group (#153).
    private let diagnostics = SiriDiagnostics(store: InMemoryKeyValueStore())

    private func audio(title: String, url: String) -> AudioModel {
        var model = AudioModel()
        model.title = title
        model.url = URL(string: url)
        return model
    }

    func test_publish_donatesContext_setsVocabulary_andRefreshesShortcutParameters() throws {
        let donor = SpyMediaUserContextDonor()
        var vocabulary: [String]?
        var refreshCount = 0
        let spotlight = SpySpotlightIndexer()
        let publisher = SiriLibraryPublisher(
            mediaUserContextDonor: donor,
            spotlightIndexer: spotlight,
            vocabulary: { vocabulary = $0.compactMap { $0 as? String } },
            refreshShortcutParameters: { refreshCount += 1 },
            diagnostics: diagnostics
        )

        publisher.publish(audios: [
            audio(title: "First", url: "file:///first"),
            audio(title: "Second", url: "file:///second")
        ])

        XCTAssertEqual(donor.donatedCounts, [2])
        XCTAssertEqual(spotlight.indexedTitles, [["First", "Second"]])
        XCTAssertEqual(vocabulary, ["First", "Second"])
        XCTAssertEqual(refreshCount, 1)
    }

    /// #157: a publish is logged with its book count, not just recorded in `SiriDiagnostics`, and
    /// its end once Spotlight has finished. Never the titles.
    func test_publish_logsTheBookCount_withoutTitles() {
        let log = RecordingSiriLogSink()
        var clock = Date(timeIntervalSince1970: 1000)
        let spotlight = SpySpotlightIndexer()
        spotlight.completesImmediately = false
        let publisher = SiriLibraryPublisher(
            mediaUserContextDonor: SpyMediaUserContextDonor(),
            spotlightIndexer: spotlight,
            vocabulary: { _ in },
            refreshShortcutParameters: {},
            log: log,
            diagnostics: diagnostics,
            now: { clock }
        )
        let done = expectation(description: "publish completed")

        publisher.publish(audios: [
            audio(title: "HiddenOne157", url: "file:///first"),
            audio(title: "HiddenTwo157", url: "file:///second"),
            audio(title: "HiddenThree157", url: "file:///third")
        ]) { done.fulfill() }
        // #173: the duration runs from the publish's start to Spotlight's completion.
        clock = clock.addingTimeInterval(2.5)
        spotlight.pendingCompletion?()
        wait(for: [done], timeout: 1)

        XCTAssertEqual(log.events, [.publishStarted(bookCount: 3), .publishFinished(milliseconds: 2500)])
        XCTAssertFalse(log.events.contains { String(describing: $0).contains("Hidden") }, "\(log.events)")
    }

    /// #159: the publish completes once Spotlight has finished indexing, after the synchronous
    /// registrations (the App Shortcut parameter update has no completion to wait for).
    func test_publish_completesAfterSpotlightFinishesIndexing() throws {
        let spotlight = SpySpotlightIndexer()
        spotlight.completesImmediately = false
        var refreshCount = 0
        let publisher = SiriLibraryPublisher(
            mediaUserContextDonor: SpyMediaUserContextDonor(),
            spotlightIndexer: spotlight,
            vocabulary: { _ in },
            refreshShortcutParameters: { refreshCount += 1 },
            diagnostics: diagnostics
        )
        var completed = false
        let done = expectation(description: "publish completed")

        publisher.publish(audios: [audio(title: "Dune", url: "file:///dune")]) {
            completed = true
            done.fulfill()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertFalse(completed, "Spotlight is still indexing")
        XCTAssertEqual(refreshCount, 1, "the shortcut update ran before the publish completed")

        try XCTUnwrap(spotlight.pendingCompletion)()
        wait(for: [done], timeout: 1)
    }

    /// Indexing reports completion even when it fails, and the failure is logged by domain/code.
    func test_spotlightIndexer_completes_andLogsAFailure() {
        let log = RecordingSiriLogSink()
        let indexer = LibrarySpotlightIndexer(
            clearItems: { done in done(nil) },
            deleteItems: { _, done in done(nil) },
            indexItems: { _, done in
                done(NSError(
                    domain: "CSIndexErrorDomain",
                    code: -1003,
                    userInfo: [NSLocalizedDescriptionKey: "SpotlightSecret159"]
                ))
            },
            store: InMemoryKeyValueStore(),
            log: log
        )
        var completed = false

        indexer.index(audios: [audio(title: "SpotlightSecret159", url: "file:///s")]) { completed = true }

        XCTAssertTrue(completed)
        XCTAssertEqual(log.events, [.spotlightIndexingFailed(domain: "CSIndexErrorDomain", code: -1003)])
        XCTAssertFalse(log.events.contains { String(describing: $0).contains("SpotlightSecret159") })
    }

    /// A first publish (no record yet) logs only that it rebuilt the index, by count.
    func test_spotlightIndexer_success_logsOnlyTheRebuild() {
        let log = RecordingSiriLogSink()
        let indexer = LibrarySpotlightIndexer(
            clearItems: { done in done(nil) },
            deleteItems: { _, done in done(nil) },
            indexItems: { _, done in done(nil) },
            store: InMemoryKeyValueStore(),
            log: log
        )
        var completed = false

        indexer.index(audios: [audio(title: "Fine", url: "file:///fine")]) { completed = true }

        XCTAssertTrue(completed)
        XCTAssertEqual(log.events, [.spotlightRebuilt(itemCount: 1, reason: .noRecord)])
    }

    /// #195: an empty library still clears the index (its last book was just deleted), and indexes
    /// nothing.
    func test_spotlightIndexer_emptyLibrary_clearsAndCompletesWithoutIndexing() {
        var clears = 0
        var indexCalls = 0
        var completed = false
        LibrarySpotlightIndexer(
            clearItems: { done in clears += 1; done(nil) },
            deleteItems: { _, done in done(nil) },
            indexItems: { _, _ in indexCalls += 1 },
            store: InMemoryKeyValueStore(),
            log: RecordingSiriLogSink()
        ).index(audios: []) { completed = true }
        XCTAssertEqual(clears, 1)
        XCTAssertEqual(indexCalls, 0)
        XCTAssertTrue(completed)
    }

    func test_spotlightItem_carriesTitleAndStableIdentifier() throws {
        let item = try XCTUnwrap(
            LibrarySpotlightIndexer.searchableItem(for: audio(title: "Dune", url: "file:///dune"))
        )
        XCTAssertEqual(item.uniqueIdentifier, "file:///dune")
        XCTAssertEqual(item.attributeSet.title, "Dune")
    }

    func test_spotlightItem_skipsUntitledOrUrllessBooks() {
        XCTAssertNil(LibrarySpotlightIndexer.searchableItem(for: audio(title: "", url: "file:///a")))
        var noURL = AudioModel()
        noURL.title = "Titled"
        XCTAssertNil(LibrarySpotlightIndexer.searchableItem(for: noURL))
    }

    func test_orderedTitles_putsLastPlayedFirst() throws {
        lastPlayed.save(url: try XCTUnwrap(URL(string: "file:///second")))
        let titles = SiriLibraryPublisher(lastPlayed: lastPlayed).orderedTitles(for: [
            audio(title: "First", url: "file:///first"),
            audio(title: "Second", url: "file:///second")
        ])
        XCTAssertEqual(titles, ["Second", "First"])
    }

    func test_orderedTitles_dropsEmptyTitlesAndDuplicates() {
        let titles = SiriLibraryPublisher(lastPlayed: lastPlayed).orderedTitles(for: [
            audio(title: "Dune", url: "file:///a"),
            audio(title: "", url: "file:///b"),
            audio(title: "Dune", url: "file:///c")
        ])
        XCTAssertEqual(titles, ["Dune"])
    }

    func test_orderedTitles_respectsVocabularyLimit() {
        let audios = (0..<(SiriLibraryPublisher.vocabularyLimit + 10)).map {
            audio(title: "Book \($0)", url: "file:///book\($0)")
        }
        XCTAssertEqual(
            SiriLibraryPublisher(lastPlayed: lastPlayed).orderedTitles(for: audios).count,
            SiriLibraryPublisher.vocabularyLimit
        )
    }

    func test_snapshotWrite_publishesLibraryToSiri() throws {
        let spy = SpySiriLibraryPublisher()

        LibrarySnapshotWriter(store: InMemoryKeyValueStore(), publisher: spy)
            .write(audios: [audio(title: "Dune", url: "file:///dune")])

        XCTAssertEqual(spy.publishedTitles, [["Dune"]])
    }

    func test_mediaUserContext_carriesLibraryCount() {
        let context = MediaUserContextDonor().makeContext(libraryItemCount: 7)
        XCTAssertEqual(context.numberOfLibraryItems, 7)
        XCTAssertEqual(context.subscriptionStatus, .unknown)
    }
}
