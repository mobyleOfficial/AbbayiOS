//
//  SiriContextRefresherTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

private final class CountingPublisher: SiriLibraryPublisherProtocol {
    var publishedCounts = [Int]()
    /// The last publish's completion, held so a test decides when the publish finishes.
    var pendingCompletion: (() -> Void)?

    func publish(audios: [AudioModel], completion: @escaping () -> Void) {
        publishedCounts.append(audios.count)
        pendingCompletion = completion
    }
}

/// Siri's context is re-published on foreground and on pause, at most once per
/// `minimumInterval` (#127), against an injected clock.
final class SiriContextRefresherTests: XCTestCase {
    private var now = Date(timeIntervalSinceReferenceDate: 0)
    private let publisher = CountingPublisher()
    private let library = MockLoadAllAudiosUseCase()
    private let log = RecordingSiriLogSink()

    private func makeRefresher() -> SiriContextRefresher {
        library.stub = [AudioModel(title: "One"), AudioModel(title: "Two")]
        return SiriContextRefresher(
            publisher: publisher,
            loadAllAudios: library,
            now: { [unowned self] in self.now },
            log: log
        )
    }

    /// #197: the lines `siri-library-publish.md` tells the reader to look for.
    func test_refreshes_logThePublishAndTheSkip() {
        let refresher = makeRefresher()
        refresher.refreshIfDue(.foreground)
        refresher.refreshIfDue(.pause)

        XCTAssertEqual(log.events, [
            .contextRefreshed(reason: "foreground", bookCount: 2),
            .contextRefreshSkipped(reason: "pause")
        ])
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

    /// #159: `refreshNow` reports completion when the publish does, not when it returns.
    func test_refreshNow_completesWhenThePublishCompletes() throws {
        let refresher = makeRefresher()
        var completed = false

        refresher.refreshNow(.backgroundTask) { completed = true }
        XCTAssertFalse(completed)

        try XCTUnwrap(publisher.pendingCompletion)()
        XCTAssertTrue(completed)
    }
}
