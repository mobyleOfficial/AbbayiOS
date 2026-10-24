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

    override func tearDownWithError() throws {
        SiriLibraryPublisher.shared = SiriLibraryPublisher()
        try super.tearDownWithError()
    }

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
            refreshShortcutParameters: { refreshCount += 1 }
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

    /// #157: a publish reaches the unified log with its book count, not just `SiriDiagnostics`.
    func test_publish_logsTheBookCount_withoutTitles() throws {
        let since = Date()
        let publisher = SiriLibraryPublisher(
            mediaUserContextDonor: SpyMediaUserContextDonor(),
            spotlightIndexer: SpySpotlightIndexer(),
            vocabulary: { _ in },
            refreshShortcutParameters: {}
        )

        publisher.publish(audios: [
            audio(title: "HiddenOne157", url: "file:///first"),
            audio(title: "HiddenTwo157", url: "file:///second"),
            audio(title: "HiddenThree157", url: "file:///third")
        ])

        let messages = try LoggedMessages.messages(category: "Siri", since: since)
        XCTAssertTrue(messages.contains { $0.contains("publish: 3 books") }, "\(messages)")
        XCTAssertFalse(messages.contains { $0.contains("Hidden") }, "\(messages)")
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
            refreshShortcutParameters: { refreshCount += 1 }
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
    func test_spotlightIndexer_completes_andLogsAFailure() throws {
        let since = Date()
        let indexer = LibrarySpotlightIndexer(indexItems: { _, done in
            done(NSError(domain: "CSIndexErrorDomain", code: -1003))
        })
        var completed = false

        indexer.index(audios: [audio(title: "SpotlightSecret159", url: "file:///s")]) { completed = true }

        XCTAssertTrue(completed)
        let messages = try LoggedMessages.messages(category: "Siri", since: since)
        let failure = try XCTUnwrap(messages.first { $0.contains("spotlight indexing failed") }, "\(messages)")
        XCTAssertTrue(failure.contains("CSIndexErrorDomain") && failure.contains("-1003"), failure)
        XCTAssertFalse(messages.contains { $0.contains("SpotlightSecret159") })
    }

    func test_spotlightIndexer_emptyLibrary_completesWithoutIndexing() {
        var calls = 0
        var completed = false
        LibrarySpotlightIndexer(indexItems: { _, _ in calls += 1 }).index(audios: []) { completed = true }
        XCTAssertEqual(calls, 0)
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
        SiriLibraryPublisher.shared = spy

        LibrarySnapshotWriter(store: InMemoryKeyValueStore()).write(audios: [audio(title: "Dune", url: "file:///dune")])

        XCTAssertEqual(spy.publishedTitles, [["Dune"]])
    }

    func test_mediaUserContext_carriesLibraryCount() {
        let context = MediaUserContextDonor().makeContext(libraryItemCount: 7)
        XCTAssertEqual(context.numberOfLibraryItems, 7)
        XCTAssertEqual(context.subscriptionStatus, .unknown)
    }
}
