//
//  MockBookDownloadManager.swift
//  AbbayTests
//

@testable import Abbay
import Combine
import Foundation

final class MockBookDownloadManager: BookDownloadManagerProtocol {
    let statesSubject = CurrentValueSubject<[String: BookDownloadState], Never>([:])
    private(set) var enqueued: [AudioModel] = []
    private(set) var paused: [String] = []
    private(set) var resumed: [String] = []
    private(set) var removed: [String] = []
    private(set) var restoreCallCount = 0
    private(set) var prioritized: [(chapterIndex: Int, bookID: String)] = []
    private(set) var retried: [(chapterIndex: Int, bookID: String)] = []

    var statesPublisher: AnyPublisher<[String: BookDownloadState], Never> {
        statesSubject.eraseToAnyPublisher()
    }

    func enqueue(_ book: AudioModel) { enqueued.append(book) }
    func pause(bookID: String) { paused.append(bookID) }
    func resume(bookID: String) { resumed.append(bookID) }
    func remove(bookID: String) { removed.append(bookID) }
    func restore() { restoreCallCount += 1 }
    func handleBackgroundEvents(completion: @escaping () -> Void) { completion() }
    func prioritize(chapterIndex: Int, ofBookID id: String) { prioritized.append((chapterIndex, id)) }
    func retry(chapterIndex: Int, ofBookID id: String) { retried.append((chapterIndex, id)) }
}

/// Counts subscriptions to `statesPublisher`, so tests can pin "one subscription, whatever the
/// number of books or emissions".
final class CountingMockBookDownloadManager: BookDownloadManagerProtocol {
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
    func retry(chapterIndex: Int, ofBookID id: String) { mock.retry(chapterIndex: chapterIndex, ofBookID: id) }
}
