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

    func index(audios: [AudioModel]) {
        indexedTitles.append(audios.map(\.title))
    }
}

private final class SpySiriLibraryPublisher: SiriLibraryPublisherProtocol {
    var publishedTitles = [[String]]()

    func publish(audios: [AudioModel]) {
        publishedTitles.append(audios.map(\.title))
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

    func test_spotlightIndexer_skipsIndexCallForEmptyLibrary() {
        var calls = 0
        LibrarySpotlightIndexer(indexItems: { _ in calls += 1 }).index(audios: [])
        XCTAssertEqual(calls, 0)
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
