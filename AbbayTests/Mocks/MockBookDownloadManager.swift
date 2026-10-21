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
}
