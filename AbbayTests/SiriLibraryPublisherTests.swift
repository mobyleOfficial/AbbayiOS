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

private final class SpySiriLibraryPublisher: SiriLibraryPublisherProtocol {
    var publishedTitles = [[String]]()

    func publish(audios: [AudioModel]) {
        publishedTitles.append(audios.map(\.title))
    }
}

final class SiriLibraryPublisherTests: XCTestCase {
    private let suiteName = "abbay.tests.SiriLibraryPublisherTests"

    override func setUpWithError() throws {
        try super.setUpWithError()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        LastPlayedStore.defaults = defaults
        LastPlayedStore.standardFallback = defaults
    }

    override func tearDownWithError() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        LastPlayedStore.defaults = AppGroup.defaults
        LastPlayedStore.standardFallback = .standard
        LibrarySnapshotWriter.defaults = AppGroup.defaults
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
        let publisher = SiriLibraryPublisher(
            mediaUserContextDonor: donor,
            vocabulary: { vocabulary = $0.compactMap { $0 as? String } },
            refreshShortcutParameters: { refreshCount += 1 }
        )

        publisher.publish(audios: [
            audio(title: "First", url: "file:///first"),
            audio(title: "Second", url: "file:///second")
        ])

        XCTAssertEqual(donor.donatedCounts, [2])
        XCTAssertEqual(vocabulary, ["First", "Second"])
        XCTAssertEqual(refreshCount, 1)
    }

    func test_orderedTitles_putsLastPlayedFirst() throws {
        LastPlayedStore.save(url: try XCTUnwrap(URL(string: "file:///second")))
        let titles = SiriLibraryPublisher().orderedTitles(for: [
            audio(title: "First", url: "file:///first"),
            audio(title: "Second", url: "file:///second")
        ])
        XCTAssertEqual(titles, ["Second", "First"])
    }

    func test_orderedTitles_dropsEmptyTitlesAndDuplicates() {
        let titles = SiriLibraryPublisher().orderedTitles(for: [
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
            SiriLibraryPublisher().orderedTitles(for: audios).count,
            SiriLibraryPublisher.vocabularyLimit
        )
    }

    func test_snapshotWrite_publishesLibraryToSiri() throws {
        let spy = SpySiriLibraryPublisher()
        SiriLibraryPublisher.shared = spy
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        LibrarySnapshotWriter.defaults = defaults

        LibrarySnapshotWriter().write(audios: [audio(title: "Dune", url: "file:///dune")])

        XCTAssertEqual(spy.publishedTitles, [["Dune"]])
    }

    func test_mediaUserContext_carriesLibraryCount() {
        let context = MediaUserContextDonor().makeContext(libraryItemCount: 7)
        XCTAssertEqual(context.numberOfLibraryItems, 7)
        XCTAssertEqual(context.subscriptionStatus, .unknown)
    }
}
