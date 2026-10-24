//
//  DownloadStateStoreTests.swift
//  AbbayTests
//

@testable import Abbay
import Combine
import Observation
import XCTest

/// Counts subscriptions to `statesPublisher`, so tests can pin "one subscription, whatever the
/// number of books or emissions".
private final class CountingMockBookDownloadManager: BookDownloadManagerProtocol {
    let mock = MockBookDownloadManager()
    private(set) var subscriptionCount = 0

    var statesPublisher: AnyPublisher<[String: BookDownloadState], Never> {
        mock.statesSubject
            .handleEvents(receiveSubscription: { [weak self] _ in self?.subscriptionCount += 1 })
            .eraseToAnyPublisher()
    }

    func enqueue(_ book: AudioModel) { mock.enqueue(book) }
    func pause(bookID: String) { mock.pause(bookID: bookID) }
    func resume(bookID: String) { mock.resume(bookID: bookID) }
    func remove(bookID: String) { mock.remove(bookID: bookID) }
    func restore() { mock.restore() }
    func handleBackgroundEvents(completion: @escaping () -> Void) { mock.handleBackgroundEvents(completion: completion) }
    func prioritize(chapterIndex: Int, ofBookID id: String) { mock.prioritize(chapterIndex: chapterIndex, ofBookID: id) }
}

/// The one app-wide download source, split per book so one book's progress only reaches the rows
/// that show that book.
@MainActor
final class DownloadStateStoreTests: XCTestCase {
    private func downloading(_ fraction: Double) -> BookDownloadState {
        BookDownloadState(chapters: [.downloading(fraction: fraction), .waiting], isPaused: false, fraction: fraction / 2)
    }

    private let complete = BookDownloadState(chapters: [.downloaded, .downloaded], isPaused: false, fraction: 1)

    func test_subscribesToStatesPublisherOnce() {
        let downloads = CountingMockBookDownloadManager()
        let store = DownloadStateStore(downloads: downloads)
        _ = store.entry(for: "a")
        _ = store.entry(for: "b")

        for step in 0..<20 { downloads.mock.statesSubject.send(["a": downloading(Double(step) / 20)]) }

        XCTAssertEqual(downloads.subscriptionCount, 1)
        withExtendedLifetime(store) {}
    }

    func test_oneBookProgress_doesNotNotifyAnotherBooksEntry() {
        let downloads = MockBookDownloadManager()
        let store = DownloadStateStore(downloads: downloads)
        let other = store.entry(for: "b")
        _ = store.entry(for: "a")
        downloads.statesSubject.send(["a": downloading(0.1), "b": downloading(0.5)])
        var fired = false
        withObservationTracking({ _ = other.state }, onChange: { fired = true })

        downloads.statesSubject.send(["a": downloading(0.2), "b": downloading(0.5)])
        downloads.statesSubject.send(["a": downloading(0.3), "b": downloading(0.5)])

        XCTAssertFalse(fired)
        XCTAssertEqual(store.entry(for: "a").state, downloading(0.3))
    }

    func test_changedBook_notifiesItsOwnEntry() {
        let downloads = MockBookDownloadManager()
        let store = DownloadStateStore(downloads: downloads)
        let entry = store.entry(for: "a")
        var fired = false
        withObservationTracking({ _ = entry.state }, onChange: { fired = true })

        downloads.statesSubject.send(["a": downloading(0.2)])

        XCTAssertTrue(fired)
        XCTAssertEqual(entry.state, downloading(0.2))
    }

    func test_completeState_mapsToNil() {
        let downloads = MockBookDownloadManager()
        let store = DownloadStateStore(downloads: downloads)
        let entry = store.entry(for: "a")
        downloads.statesSubject.send(["a": downloading(0.5)])
        XCTAssertNotNil(entry.state)

        downloads.statesSubject.send(["a": complete])

        XCTAssertNil(entry.state)
    }

    func test_entryAskedAfterEmission_startsFromLatestState() {
        let downloads = MockBookDownloadManager()
        let store = DownloadStateStore(downloads: downloads)
        downloads.statesSubject.send(["a": downloading(0.4), "done": complete])

        XCTAssertEqual(store.entry(for: "a").state, downloading(0.4))
        XCTAssertNil(store.entry(for: "done").state)
        XCTAssertNil(store.entry(for: "unknown").state)
    }

    func test_bookDroppedFromTheMap_clearsItsEntry() {
        let downloads = MockBookDownloadManager()
        let store = DownloadStateStore(downloads: downloads)
        let entry = store.entry(for: "a")
        downloads.statesSubject.send(["a": downloading(0.4)])

        downloads.statesSubject.send([:])

        XCTAssertNil(entry.state)
    }

    func test_entryIdentity_isStable() {
        let store = DownloadStateStore(downloads: MockBookDownloadManager())

        XCTAssertTrue(store.entry(for: "a") === store.entry(for: "a"))
        XCTAssertFalse(store.entry(for: "a") === store.entry(for: "b"))
    }

    func test_pauseAndResume_forwardToTheManager() {
        let downloads = MockBookDownloadManager()
        let store = DownloadStateStore(downloads: downloads)

        store.pause(bookID: "a")
        store.resume(bookID: "b")

        XCTAssertEqual(downloads.paused, ["a"])
        XCTAssertEqual(downloads.resumed, ["b"])
    }
}
