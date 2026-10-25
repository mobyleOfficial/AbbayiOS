//
//  LibrarySnapshotOnMutationTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// #85: the use cases that change the library rewrite the App Group snapshot themselves, once per
/// call however many books it carries, so no caller can forget it and none does it twice. The
/// write publishes to Siri (#84) and posts `.libraryDidChange` for CarPlay (#95), so "once" holds
/// for those too.
final class LibrarySnapshotOnMutationTests: XCTestCase {
    private let urls = (1...3).compactMap { URL(string: "file:///snapshot-on-mutation/\($0).m4a") }

    override func tearDown() {
        DeleteAudioUseCase(
            removeDownloads: { _ in },
            forgetSettings: { _ in },
            snapshotWriter: MockLibrarySnapshotWriter()
        ).execute(urls.map { AudioModel(url: $0) })
        super.tearDown()
    }

    private func books(_ count: Int) -> [AudioModel] {
        urls.prefix(count).enumerated().map { index, url in
            AudioModel(title: "Book \(index + 1)", url: url)
        }
    }

    // MARK: - Save

    func test_save_oneBook_refreshesTheSnapshotOnce() throws {
        let writer = MockLibrarySnapshotWriter()

        try SaveAudioUseCase(snapshotWriter: writer).execute(books(1)[0])

        XCTAssertEqual(writer.refreshCallCount, 1)
    }

    /// An import of several files is one save, so one write.
    func test_save_severalBooks_refreshesTheSnapshotOnce() throws {
        let writer = MockLibrarySnapshotWriter()

        try SaveAudioUseCase(snapshotWriter: writer).execute(books(3))

        XCTAssertEqual(writer.refreshCallCount, 1)
        XCTAssertEqual(LoadAudioUseCase().execute(url: urls[2])?.title, "Book 3")
    }

    func test_save_nothing_leavesTheSnapshotAlone() throws {
        let writer = MockLibrarySnapshotWriter()

        try SaveAudioUseCase(snapshotWriter: writer).execute([])

        XCTAssertEqual(writer.refreshCallCount, 0)
    }

    // MARK: - Delete

    private final class NoopDeleteRepository: DeleteAudioRepositoryProtocol {
        private(set) var deletedURLs: [URL?] = []

        func execute(url: URL?) { deletedURLs.append(url) }
    }

    private func makeDelete(
        writer: MockLibrarySnapshotWriter,
        repository: NoopDeleteRepository = NoopDeleteRepository()
    ) -> DeleteAudioUseCase {
        DeleteAudioUseCase(
            repository: repository,
            removeDownloads: { _ in },
            forgetSettings: { _ in },
            snapshotWriter: writer
        )
    }

    func test_delete_oneBook_refreshesTheSnapshotOnce() {
        let writer = MockLibrarySnapshotWriter()

        makeDelete(writer: writer).execute(books(1)[0])

        XCTAssertEqual(writer.refreshCallCount, 1)
    }

    /// Settings' "Delete finished downloads" removes several books in one call: one write.
    func test_delete_severalBooks_deletesEachAndRefreshesOnce() {
        let writer = MockLibrarySnapshotWriter()
        let repository = NoopDeleteRepository()

        makeDelete(writer: writer, repository: repository).execute(books(3))

        XCTAssertEqual(repository.deletedURLs, urls)
        XCTAssertEqual(writer.refreshCallCount, 1)
    }

    func test_delete_nothing_leavesTheSnapshotAlone() {
        let writer = MockLibrarySnapshotWriter()

        makeDelete(writer: writer).execute([])

        XCTAssertEqual(writer.refreshCallCount, 0)
    }

    // MARK: - Through the real writer

    private final class PublishCountingSpy: SiriLibraryPublisherProtocol {
        private(set) var publishedTitles: [[String]] = []

        func publish(audios: [AudioModel], completion: @escaping () -> Void) {
            publishedTitles.append(audios.map(\.title))
            completion()
        }
    }

    /// Save then delete, through the real writer: the snapshot follows the library, and each
    /// change publishes to Siri and tells CarPlay exactly once.
    func test_saveAndDelete_writeTheSnapshotPublishAndNotifyOnceEach() throws {
        let appGroup = InMemoryKeyValueStore()
        let library = MockLoadAllAudiosUseCase()
        let spy = PublishCountingSpy()
        let writer = LibrarySnapshotWriter(store: appGroup, loadAllAudios: library, publisher: spy)
        let changed = expectation(forNotification: .libraryDidChange, object: nil)
        changed.expectedFulfillmentCount = 2
        changed.assertForOverFulfill = true

        library.stub = books(2)
        try SaveAudioUseCase(snapshotWriter: writer).execute(books(2))
        XCTAssertEqual(LibrarySnapshotReader(store: appGroup).read().map(\.title), ["Book 1", "Book 2"])

        library.stub = Array(books(2).suffix(1))
        DeleteAudioUseCase(
            repository: NoopDeleteRepository(),
            removeDownloads: { _ in },
            forgetSettings: { _ in },
            snapshotWriter: writer
        ).execute(books(1))
        XCTAssertEqual(LibrarySnapshotReader(store: appGroup).read().map(\.title), ["Book 2"])

        XCTAssertEqual(spy.publishedTitles, [["Book 1", "Book 2"], ["Book 2"]])
        wait(for: [changed], timeout: 1)
    }
}
