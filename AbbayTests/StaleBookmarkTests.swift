//
//  StaleBookmarkTests.swift
//  AbbayTests
//

@testable import Abbay
import CoreData
import XCTest

/// #146: a bookmark that resolves as stale is recreated, and the new one is saved to the book's
/// row through the save use case, once. Before, it was recreated and dropped on every load.
///
/// A really stale bookmark can't be made on demand, so the resolver is stubbed; the rows are real
/// Core Data.
final class StaleBookmarkTests: XCTestCase {
    private let firstURL = URL(fileURLWithPath: "/stale-bookmark-tests/first.m4b")
    private let secondURL = URL(fileURLWithPath: "/stale-bookmark-tests/second.m4b")
    /// Where the bookmarks resolve to: a file that was moved since its bookmark was made.
    private let movedURL = URL(fileURLWithPath: "/stale-bookmark-tests/moved/first.m4b")
    private let storedBookmark = Data([1, 1, 1])
    private let freshBookmark = Data([2, 2, 2])

    override func tearDown() {
        removeBooks()
        super.tearDown()
    }

    // MARK: - LoadAudioUseCase

    func test_load_staleBookmark_isSavedOnce() throws {
        try insert(firstURL)
        let save = MockSaveAudioUseCase()
        let sut = LoadAudioUseCase(resolveBookmark: stale, staleBookmarks: StaleBookmarkSaver(save: { save }))

        let loaded = try XCTUnwrap(sut.execute(url: firstURL))
        _ = sut.execute(url: firstURL)

        XCTAssertEqual(save.batches.count, 1, "re-saved once, not on every load")
        let saved = try XCTUnwrap(save.savedModels.first)
        XCTAssertEqual(saved.url, firstURL, "saved under the row's own URL, so no second row is inserted")
        XCTAssertEqual(saved.bookmarkData, freshBookmark)
        XCTAssertEqual(saved.title, "Book")
        XCTAssertEqual(loaded.bookmarkData, freshBookmark, "the caller gets the fresh bookmark too")
        XCTAssertEqual(loaded.fileURL, movedURL, "and the file the bookmark points at")
        XCTAssertEqual(loaded.url, firstURL, "still identified by its row (#186)")
    }

    func test_load_freshBookmark_isNotSaved() throws {
        try insert(firstURL)
        let save = MockSaveAudioUseCase()
        let sut = LoadAudioUseCase(resolveBookmark: fresh, staleBookmarks: StaleBookmarkSaver(save: { save }))

        let loaded = try XCTUnwrap(sut.execute(url: firstURL))

        XCTAssertEqual(save.batches.count, 0)
        XCTAssertEqual(loaded.bookmarkData, storedBookmark)
    }

    /// With the real save use case the row holds the fresh bookmark afterwards, and it is still
    /// one row.
    func test_load_staleBookmark_realSave_storesTheFreshBookmarkInTheRow() throws {
        try insert(firstURL)
        let save = SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter())
        let sut = LoadAudioUseCase(resolveBookmark: stale, staleBookmarks: StaleBookmarkSaver(save: { save }))

        _ = sut.execute(url: firstURL)

        XCTAssertEqual(storedBookmarks(firstURL), [freshBookmark])
        XCTAssertEqual(storedBookmarks(movedURL).count, 0)
    }

    // MARK: - LoadAllAudiosUseCase

    /// The library's load re-saves every stale book in one call: one Core Data save, one snapshot.
    func test_loadAll_staleBookmarks_areSavedInOneCall_once() throws {
        try insert(firstURL)
        try insert(secondURL)
        let save = MockSaveAudioUseCase()
        let staleBookmarks = StaleBookmarkSaver(save: { save })
        let sut = LoadAllAudiosUseCase(resolveBookmark: stale, staleBookmarks: staleBookmarks)

        _ = sut.execute()
        _ = sut.execute()
        _ = LoadAudioUseCase(resolveBookmark: stale, staleBookmarks: staleBookmarks).execute(url: firstURL)

        XCTAssertEqual(save.batches.count, 1)
        XCTAssertEqual(Set(save.savedModels.compactMap(\.url)), [firstURL, secondURL])
    }

    func test_loadAll_freshBookmarks_areNotSaved() throws {
        try insert(firstURL)
        let save = MockSaveAudioUseCase()
        let sut = LoadAllAudiosUseCase(resolveBookmark: fresh, staleBookmarks: StaleBookmarkSaver(save: { save }))

        _ = sut.execute()

        XCTAssertEqual(save.batches.count, 0)
    }

    // MARK: - URL.resolveBookmarkRefreshing

    /// A bookmark made just now isn't stale: nothing to save.
    func test_resolveBookmarkRefreshing_freshBookmark_hasNoRefreshedData() throws {
        let url = try TestFixtures.christmastideURL()
        let data = try XCTUnwrap(url.createBookmarkData())

        let resolved = try XCTUnwrap(URL.resolveBookmarkRefreshing(from: data))

        XCTAssertEqual(resolved.url.standardizedFileURL, url.standardizedFileURL)
        XCTAssertNil(resolved.refreshedData)
    }

    // MARK: - Helpers

    /// Only this test's bookmark is stubbed: the store is shared, and other tests (or the app
    /// host's seed) may leave rows of their own, which resolve for real.
    private func stale(_ data: Data?) -> ResolvedBookmark? {
        guard data == storedBookmark else { return URL.resolveBookmarkRefreshing(from: data) }
        return ResolvedBookmark(url: movedURL, refreshedData: freshBookmark)
    }

    private func fresh(_ data: Data?) -> ResolvedBookmark? {
        guard data == storedBookmark else { return URL.resolveBookmarkRefreshing(from: data) }
        return ResolvedBookmark(url: movedURL, refreshedData: nil)
    }

    private func insert(_ url: URL) throws {
        var audio = AudioModel()
        audio.title = "Book"
        audio.url = url
        audio.bookmarkData = storedBookmark
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(audio)
    }

    /// The stored bookmark of each row with this URL.
    private func storedBookmarks(_ url: URL) -> [Data?] {
        LocalStorage.persistent.performAndWait { context in
            let request = AudioDataModel.fetchRequest()
            request.predicate = NSPredicate(format: "url == %@", url as NSURL)
            return ((try? context.fetch(request)) ?? []).map(\.bookmarkData)
        }
    }

    private func removeBooks() {
        LocalStorage.persistent.performAndWait { context in
            for url in [firstURL, secondURL, movedURL] {
                let request = AudioDataModel.fetchRequest()
                request.predicate = NSPredicate(format: "url == %@", url as NSURL)
                for book in (try? context.fetch(request)) ?? [] {
                    context.delete(book)
                }
            }
        }
        LocalStorage.persistent.saveContext()
    }
}
