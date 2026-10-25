//
//  MovedBookKeyMigrationTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// #186: before a book was keyed by its row everywhere, the player saved a moved book's last-played
/// pointer and speed under the URL its file resolved to. Those keys move to the row's URL the first
/// time the library loads the book, so an upgrade keeps them (on-disk compatibility, #143).
final class MovedBookKeyMigrationTests: XCTestCase {
    private let rowURL = URL(fileURLWithPath: "/key-migration/book.m4b")
    private let resolvedURL = URL(fileURLWithPath: "/key-migration/moved/book.m4b")
    private var appGroup = InMemoryKeyValueStore()
    private var settings = AppSettings(store: InMemoryKeyValueStore())

    override func setUp() {
        super.setUp()
        appGroup = InMemoryKeyValueStore()
        settings = AppSettings(store: InMemoryKeyValueStore())
    }

    private var lastPlayed: LastPlayedStore { .inMemory(appGroup) }

    private func migration() -> MovedBookKeyMigration {
        let stores = MovedBookKeyStores(lastPlayed: lastPlayed, speeds: settings)
        return MovedBookKeyMigration(stores: { stores })
    }

    private func movedBook() -> AudioModel {
        var book = AudioModel(title: "Book", url: rowURL)
        book.resolvedURL = resolvedURL
        return book
    }

    // MARK: - Last played

    func test_lastPlayedUnderTheResolvedURL_movesToTheRow() {
        lastPlayed.save(url: resolvedURL)

        migration().migrate([movedBook()])

        XCTAssertEqual(lastPlayed.lastPlayedURL(), rowURL)
    }

    func test_lastPlayedOfAnotherBook_isLeftAlone() throws {
        let other = try XCTUnwrap(URL(string: "file:///key-migration/other.m4b"))
        lastPlayed.save(url: other)

        migration().migrate([movedBook()])

        XCTAssertEqual(lastPlayed.lastPlayedURL(), other)
    }

    // MARK: - Speed

    func test_speedUnderTheResolvedURL_movesToTheRow() {
        settings.setSpeed(1.75, for: resolvedURL)

        migration().migrate([movedBook()])

        XCTAssertEqual(settings.playbackSpeed(for: rowURL), 1.75)
        XCTAssertNil(settings.bookSpeeds[resolvedURL.absoluteString], "no orphan key left behind")
        XCTAssertEqual(settings.speed(for: rowURL), 1.75, "the copy views read follows")
    }

    func test_speedUnderBoth_keepsTheRowsAndDropsTheResolvedOne() {
        settings.setSpeed(1.25, for: rowURL)
        settings.setSpeed(2, for: resolvedURL)

        migration().migrate([movedBook()])

        XCTAssertEqual(settings.playbackSpeed(for: rowURL), 1.25)
        XCTAssertNil(settings.bookSpeeds[resolvedURL.absoluteString])
    }

    // MARK: - Books that didn't move

    func test_bookThatDidNotMove_changesNothing() {
        lastPlayed.save(url: rowURL)
        settings.setSpeed(1.5, for: rowURL)

        migration().migrate([AudioModel(title: "Book", url: rowURL)])

        XCTAssertEqual(lastPlayed.lastPlayedURL(), rowURL)
        XCTAssertEqual(settings.bookSpeeds, [rowURL.absoluteString: 1.5])
    }

    func test_noStores_doesNothing() {
        lastPlayed.save(url: resolvedURL)

        MovedBookKeyMigration(stores: { nil }).migrate([movedBook()])

        XCTAssertEqual(lastPlayed.lastPlayedURL(), resolvedURL)
    }

    // MARK: - Through the library load

    func test_loadingTheLibrary_migratesAMovedBooksKeys() throws {
        let bookmark = Data([4, 4, 4])
        try insertRow(bookmark: bookmark)
        defer { removeRow() }
        lastPlayed.save(url: resolvedURL)
        settings.setSpeed(1.5, for: resolvedURL)
        let resolve: (Data?) -> ResolvedBookmark? = { [resolvedURL] data in
            data == bookmark ? ResolvedBookmark(url: resolvedURL, refreshedData: nil) : nil
        }

        _ = LoadAllAudiosUseCase(
            resolveBookmark: resolve,
            staleBookmarks: StaleBookmarkSaver(save: { MockSaveAudioUseCase() }),
            movedBooks: migration()
        ).execute()

        XCTAssertEqual(lastPlayed.lastPlayedURL(), rowURL)
        XCTAssertEqual(settings.playbackSpeed(for: rowURL), 1.5)
    }

    func test_loadingOneBook_migratesItsKeys() throws {
        let bookmark = Data([5, 5, 5])
        try insertRow(bookmark: bookmark)
        defer { removeRow() }
        lastPlayed.save(url: resolvedURL)
        let resolve: (Data?) -> ResolvedBookmark? = { [resolvedURL] data in
            data == bookmark ? ResolvedBookmark(url: resolvedURL, refreshedData: nil) : nil
        }

        _ = LoadAudioUseCase(
            resolveBookmark: resolve,
            staleBookmarks: StaleBookmarkSaver(save: { MockSaveAudioUseCase() }),
            movedBooks: migration()
        ).execute(url: rowURL)

        XCTAssertEqual(lastPlayed.lastPlayedURL(), rowURL)
    }

    // MARK: - Helpers

    private func insertRow(bookmark: Data) throws {
        removeRow()
        var audio = AudioModel(title: "Key Migration Book", duration: 100, url: rowURL)
        audio.bookmarkData = bookmark
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(audio)
    }

    private func removeRow() {
        LocalStorage.persistent.performAndWait { context in
            let request = AudioDataModel.fetchRequest()
            request.predicate = NSPredicate(format: "url == %@", rowURL as NSURL)
            for book in (try? context.fetch(request)) ?? [] {
                context.delete(book)
            }
        }
        LocalStorage.persistent.saveContext()
    }
}
