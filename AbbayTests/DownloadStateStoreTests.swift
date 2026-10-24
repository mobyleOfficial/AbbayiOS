//
//  DownloadStateStoreTests.swift
//  AbbayTests
//

@testable import Abbay
import Combine
import Observation
import XCTest

/// The one app-wide download source, split per book so one book's progress only reaches the rows
/// that show that book.
@MainActor
final class DownloadStateStoreTests: XCTestCase {
    private func downloading(_ fraction: Double) -> BookDownloadState {
        BookDownloadState(
            chapters: [.downloading(fraction: fraction), .waiting],
            isPaused: false,
            fraction: fraction / 2
        )
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

    // MARK: - Low Data Mode (#148)

    func test_lowDataMode_followsThePath_andNotifiesOnlyOnChange() {
        let path = FakeNetworkPath()
        let store = DownloadStateStore(downloads: MockBookDownloadManager(), path: path)
        XCTAssertFalse(store.lowDataMode.isOn)
        var fired = 0
        withObservationTracking({ _ = store.lowDataMode.isOn }, onChange: { fired += 1 })

        path.isLowDataMode = true

        XCTAssertTrue(store.lowDataMode.isOn)
        XCTAssertEqual(fired, 1)
        path.isLowDataMode = false
        XCTAssertFalse(store.lowDataMode.isOn)
    }

    func test_isHeldByLowDataMode_onlyForAnUnpausedWiFiOnlyBookStillDownloading() {
        let paused = BookDownloadState(chapters: [.waiting], isPaused: true, fraction: 0)
        let held = DownloadStateStore.isHeldByLowDataMode(_:allowsCellular:isLowDataMode:)

        XCTAssertTrue(held(downloading(0.1), false, true))
        XCTAssertFalse(held(downloading(0.1), true, true), "Cellular allowed: Low Data Mode doesn't hold it")
        XCTAssertFalse(held(downloading(0.1), false, false), "Not in Low Data Mode")
        XCTAssertFalse(held(paused, false, true), "Paused says so itself")
        XCTAssertFalse(held(complete, false, true))
        XCTAssertFalse(held(nil, false, true))
    }

    func test_isHeldByLowDataMode_forABook_readsItsEntryAndCellularFlag() {
        let downloads = MockBookDownloadManager()
        let path = FakeNetworkPath()
        let store = DownloadStateStore(downloads: downloads, path: path)
        downloads.statesSubject.send(["a": downloading(0.1)])
        path.isLowDataMode = true

        XCTAssertTrue(store.isHeldByLowDataMode(bookID: "a", allowsCellular: false))
        XCTAssertFalse(store.isHeldByLowDataMode(bookID: "a", allowsCellular: true))
        XCTAssertFalse(store.isHeldByLowDataMode(bookID: "other", allowsCellular: false))
    }
}
