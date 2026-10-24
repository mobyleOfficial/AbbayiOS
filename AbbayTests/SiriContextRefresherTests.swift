//
//  SiriContextRefresherTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

private final class CountingPublisher: SiriLibraryPublisherProtocol {
    var publishedCounts = [Int]()

    func publish(audios: [AudioModel]) {
        publishedCounts.append(audios.count)
    }
}

/// Siri's context is re-published on foreground and on pause, at most once per
/// `minimumInterval` (#127), against an injected clock.
final class SiriContextRefresherTests: XCTestCase {
    private var now = Date(timeIntervalSinceReferenceDate: 0)
    private let publisher = CountingPublisher()
    private let library = MockLoadAllAudiosUseCase()

    private func makeRefresher() -> SiriContextRefresher {
        library.stub = [AudioModel(title: "One"), AudioModel(title: "Two")]
        return SiriContextRefresher(
            publisher: publisher,
            loadAllAudios: library,
            now: { [unowned self] in self.now }
        )
    }

    func test_refreshIfDue_firstCall_publishesTheLibrary() {
        let refresher = makeRefresher()

        refresher.refreshIfDue(.foreground)

        XCTAssertEqual(publisher.publishedCounts, [2])
    }

    func test_refreshIfDue_withinTheInterval_doesNotPublishAgain() {
        let refresher = makeRefresher()
        refresher.refreshIfDue(.foreground)

        now = now.addingTimeInterval(SiriContextRefresher.minimumInterval - 1)
        refresher.refreshIfDue(.pause)

        XCTAssertEqual(publisher.publishedCounts.count, 1)
        XCTAssertEqual(library.executeCallCount, 1, "a throttled refresh doesn't even read the library")
    }

    func test_refreshIfDue_afterTheInterval_publishesAgain() {
        let refresher = makeRefresher()
        refresher.refreshIfDue(.foreground)

        now = now.addingTimeInterval(SiriContextRefresher.minimumInterval)
        refresher.refreshIfDue(.pause)

        XCTAssertEqual(publisher.publishedCounts.count, 2)
    }

    func test_minimumInterval_isTenMinutes() {
        XCTAssertEqual(SiriContextRefresher.minimumInterval, 10 * 60)
    }

    /// Launch publishes through the snapshot writer, then the scene becomes active: that first
    /// foreground must not publish a second time.
    func test_markPublished_startsTheInterval() {
        let refresher = makeRefresher()

        refresher.markPublished()
        refresher.refreshIfDue(.foreground)

        XCTAssertTrue(publisher.publishedCounts.isEmpty)
    }

    func test_refreshNow_ignoresTheThrottle_andRestartsIt() {
        let refresher = makeRefresher()
        refresher.refreshIfDue(.foreground)

        refresher.refreshNow(.backgroundTask)
        now = now.addingTimeInterval(SiriContextRefresher.minimumInterval - 1)
        refresher.refreshIfDue(.pause)

        XCTAssertEqual(publisher.publishedCounts.count, 2)
    }
}
