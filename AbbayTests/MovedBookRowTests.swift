//
//  MovedBookRowTests.swift
//  AbbayTests
//

@testable import Abbay
import CoreData
import XCTest

/// #176: a book whose bookmark resolves somewhere other than the URL its row was saved under (the
/// file moved, or the app was reinstalled and the bundle moved). The loaded model plays from the
/// resolved URL (`fileURL`), but every row operation must find the row by the URL it is stored
/// under (`url`, the book's identity since #186), or a
/// delete silently does nothing and `-resetLibrary` leaves the book behind.
///
/// The resolver is stubbed (a moved file can't be made on demand); the rows are real Core Data.
final class MovedBookRowTests: XCTestCase {
    private let storedURL = URL(fileURLWithPath: "/moved-book-row-tests/book.m4b")
    /// Where the bookmark now resolves to.
    private let movedURL = URL(fileURLWithPath: "/moved-book-row-tests/moved/book.m4b")
    private let bookmark = Data([7, 6, 5])

    override func setUpWithError() throws {
        try super.setUpWithError()
        removeBooks()
        try insertBook()
    }

    override func tearDown() {
        removeBooks()
        super.tearDown()
    }

    // MARK: - Mapping

    func test_load_movedBook_keepsItsRowURL() throws {
        let book = try loadMovedBook()

        XCTAssertEqual(book.url, storedURL, "identified by the row it came from (#186)")
        XCTAssertEqual(book.fileURL, movedURL, "plays from where the bookmark points")
    }

    func test_newModel_isOpenedAtItsURL() {
        let book = AudioModel(url: movedURL)

        XCTAssertNil(book.resolvedURL)
        XCTAssertEqual(book.fileURL, movedURL, "a book not loaded from the store is its own file")
    }

    // MARK: - Delete

    func test_delete_movedBook_removesItsRow() throws {
        let book = try loadMovedBook()

        DeleteAudioUseCase(forgetSettings: { _ in }, snapshotWriter: MockLibrarySnapshotWriter()).execute(book)

        XCTAssertEqual(rowCount(storedURL), 0, "the row is found by its stored URL, not the resolved one")
    }

    /// What `-resetLibrary` does: delete everything `LoadAllAudiosUseCase` returns.
    func test_deleteAll_withAMovedBook_leavesNothingBehind() throws {
        let all = LoadAllAudiosUseCase(resolveBookmark: moved, staleBookmarks: noStaleSaves())
        let loaded = all.execute().filter { $0.url == storedURL }
        XCTAssertEqual(loaded.count, 1)

        DeleteAudioUseCase(forgetSettings: { _ in }, snapshotWriter: MockLibrarySnapshotWriter()).execute(loaded)

        XCTAssertEqual(rowCount(storedURL), 0)
    }

    // MARK: - Save

    func test_save_movedBook_updatesItsRow_insteadOfInsertingAnother() throws {
        var book = try loadMovedBook()
        book.title = "Renamed"

        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(book)

        XCTAssertEqual(rowCount(movedURL), 0, "no second row under the resolved URL")
        XCTAssertEqual(rowTitles(storedURL), ["Renamed"], "the row keeps its key, so the other stores still match it")
    }

    // MARK: - Position

    func test_savePosition_movedBook_writesItsRow() throws {
        let book = try loadMovedBook()

        SavePlaybackPositionUseCase().execute(url: book.url, currentTime: 42, bookmarkData: nil)

        XCTAssertEqual(rowTimes(storedURL), [42])
    }

    // MARK: - Helpers

    private func moved(_ data: Data?) -> ResolvedBookmark? {
        guard data == bookmark else { return URL.resolveBookmarkRefreshing(from: data) }
        return ResolvedBookmark(url: movedURL, refreshedData: nil)
    }

    private func noStaleSaves() -> StaleBookmarkSaver {
        StaleBookmarkSaver(save: { MockSaveAudioUseCase() })
    }

    private func loadMovedBook() throws -> AudioModel {
        let load = LoadAudioUseCase(resolveBookmark: moved, staleBookmarks: noStaleSaves())
        return try XCTUnwrap(load.execute(url: storedURL))
    }

    private func insertBook() throws {
        var audio = AudioModel()
        audio.title = "Book"
        audio.duration = 400
        audio.url = storedURL
        audio.bookmarkData = bookmark
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(audio)
    }

    /// Call inside `performAndWait`.
    private func rows(_ url: URL, in context: NSManagedObjectContext) -> [AudioDataModel] {
        let request = AudioDataModel.fetchRequest()
        request.predicate = NSPredicate(format: "url == %@", url as NSURL)
        return (try? context.fetch(request)) ?? []
    }

    private func rowCount(_ url: URL) -> Int {
        LocalStorage.persistent.performAndWait { context in rows(url, in: context).count }
    }

    private func rowTitles(_ url: URL) -> [String?] {
        LocalStorage.persistent.performAndWait { context in rows(url, in: context).map(\.title) }
    }

    private func rowTimes(_ url: URL) -> [Double] {
        LocalStorage.persistent.performAndWait { context in rows(url, in: context).map(\.currentTime) }
    }

    private func removeBooks() {
        LocalStorage.persistent.performAndWait { context in
            for url in [storedURL, movedURL] {
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
