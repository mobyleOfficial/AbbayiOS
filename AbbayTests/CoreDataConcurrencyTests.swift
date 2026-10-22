//
//  CoreDataConcurrencyTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// AppIntents queries the library on a background thread (`AudiobookEntityQuery`) while the main
/// thread saves to the same main-queue context. Every read must hop onto the context's queue,
/// mapping included, or Core Data crashes faulting the `chapters` relationship.
final class CoreDataConcurrencyTests: XCTestCase {
    private let urlPrefix = "abbay-test://concurrency/"
    private let bookCount = 20

    override func tearDown() {
        for index in 0..<bookCount {
            DeleteAudioUseCase(removeDownloads: { _ in }).execute(makeBook(index))
        }
        super.tearDown()
    }

    func test_loadAll_fromBackgroundThreads_whileMainSavesAndDeletes_staysConsistent() throws {
        let done = expectation(description: "background reads finished")
        let lock = NSLock()
        var reads = 0
        var violations = [String]()
        let prefix = urlPrefix

        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.concurrentPerform(iterations: 8) { _ in
                for _ in 0..<40 {
                    let books = LoadAllAudiosUseCase().execute()
                        .filter { $0.url?.absoluteString.hasPrefix(prefix) == true }
                    let broken = books.filter { $0.chapters.map(\.title) != ["One", "Two"] }
                    lock.withLock {
                        reads += 1
                        violations += broken.map { "\($0.title): \($0.chapters.map(\.title))" }
                    }
                }
            }
            done.fulfill()
        }

        // The main thread keeps writing, and spins its run loop so the readers' blocks get to run.
        for round in 0..<10 {
            for index in 0..<bookCount {
                try SaveAudioUseCase().execute(makeBook(index))
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            for index in 0..<bookCount where index % 2 == round % 2 {
                DeleteAudioUseCase(removeDownloads: { _ in }).execute(makeBook(index))
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }

        wait(for: [done], timeout: 60)
        XCTAssertEqual(lock.withLock { reads }, 8 * 40)
        XCTAssertEqual(lock.withLock { violations }, [])
    }

    func test_dataStackPerformAndWait_fromBackgroundThread_runsOnTheMainQueue() {
        let done = expectation(description: "block ran")
        DispatchQueue.global().async {
            let ranOnMain = LocalStorage.persistent.performAndWait { _ in Thread.isMainThread }
            XCTAssertTrue(ranOnMain)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    // MARK: - Helpers

    private func makeBook(_ index: Int) -> AudioModel {
        var audio = AudioModel()
        audio.title = "Concurrency \(index)"
        audio.url = URL(string: "\(urlPrefix)\(index)")
        audio.chapters = [
            ChapterModel(title: "One", startTime: 0, duration: 60, remoteURL: nil, expectedBytes: 0),
            ChapterModel(title: "Two", startTime: 60, duration: 60, remoteURL: nil, expectedBytes: 0)
        ]
        return audio
    }
}
