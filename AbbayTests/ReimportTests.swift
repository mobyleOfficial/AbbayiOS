//
//  ReimportTests.swift
//  AbbayTests
//

@testable import Abbay
import CoreData
import XCTest

/// #196: importing a moved file again from its new place relinks the book it already is, instead of
/// adding a second one. `ReimportMatcher` decides; `FileLoader` saves the relinked book to its row.
final class ReimportMatcherTests: XCTestCase {
    private let stored = URL(fileURLWithPath: "/reimport-tests/book.m4b")
    private let picked = URL(fileURLWithPath: "/reimport-tests/moved/book.m4b")

    private func book(
        _ title: String = "Book",
        url: URL,
        duration: Double = 400,
        resolvedURL: URL? = nil,
        librivoxID: String? = nil
    ) -> AudioModel {
        var model = AudioModel(title: title, duration: duration, url: url)
        model.resolvedURL = resolvedURL
        model.librivoxID = librivoxID
        return model
    }

    private func matcher(sameFiles: [(URL, URL)] = [], reachable: Set<URL> = []) -> ReimportMatcher {
        ReimportMatcher(
            isSameFile: { lhs, rhs in sameFiles.contains { $0 == (lhs, rhs) || $0 == (rhs, lhs) } },
            isReachable: { reachable.contains($0) }
        )
    }

    // MARK: - The same file

    /// The stored book's bookmark resolves to the picked file: it is that book.
    func test_aBookWhoseFileIsThePickedFile_isMatched() {
        let movedBook = book(url: stored, resolvedURL: picked)
        let other = book("Other", url: URL(fileURLWithPath: "/reimport-tests/other.m4b"))

        let match = matcher(sameFiles: [(picked, picked)], reachable: [picked])
            .existingBook(for: book("Parsed Title", url: picked, duration: 12), in: [other, movedBook])

        XCTAssertEqual(match?.url, stored)
    }

    func test_aDifferentReachableFile_isNotMatched_evenWithTheSameNameAndDuration() {
        let original = book(url: stored)

        let match = matcher(reachable: [stored, picked]).existingBook(for: book(url: picked), in: [original])

        XCTAssertNil(match, "a copy next to the original is a new book")
    }

    // MARK: - A lost book's file

    /// The moved-file notice's case: the old bookmark finds nothing, so the book is matched by its
    /// file name and duration.
    func test_aLostBook_withTheSameFileNameAndDuration_isMatched() {
        let lost = book("Stored Title", url: stored, duration: 400)

        let match = matcher().existingBook(for: book("Parsed Title", url: picked, duration: 400.4), in: [lost])

        XCTAssertEqual(match?.url, stored)
    }

    func test_aLostBook_withTheSameTitleAndDuration_isMatched_whenTheFileWasRenamed() {
        let lost = book("Dune", url: stored, duration: 400)
        let renamed = URL(fileURLWithPath: "/reimport-tests/moved/Dune (2).m4b")

        XCTAssertEqual(matcher().existingBook(for: book("Dune", url: renamed, duration: 400), in: [lost])?.url, stored)
    }

    func test_aLostBook_ofAnotherDuration_isNotMatched() {
        let lost = book(url: stored, duration: 400)

        XCTAssertNil(matcher().existingBook(for: book(url: picked, duration: 402), in: [lost]))
    }

    func test_aLostBook_withNeitherNameNorTitleInCommon_isNotMatched() {
        let lost = book("Dune", url: stored, duration: 400)
        let other = URL(fileURLWithPath: "/reimport-tests/moved/emma.m4b")

        XCTAssertNil(matcher().existingBook(for: book("Emma", url: other, duration: 400), in: [lost]))
    }

    func test_twoLostBooksThatFit_matchNeither() {
        let first = book(url: stored)
        let second = book(url: URL(fileURLWithPath: "/reimport-tests/elsewhere/book.m4b"))

        XCTAssertNil(matcher().existingBook(for: book(url: picked), in: [first, second]))
    }

    func test_aLibriVoxBook_isNeverMatched() throws {
        let libriVox = book(url: try XCTUnwrap(URL(string: "librivox://book.m4b")), librivoxID: "book_librivox")

        XCTAssertNil(matcher().existingBook(for: book(url: picked), in: [libriVox]))
    }

    // MARK: - Relinking

    func test_relink_keepsTheBooksIdentityAndPosition_withTheNewBookmark() {
        var original = book("Stored Title", url: stored)
        original.currentTime = 120
        original.bookmarkData = Data([1])
        var parsed = book("Parsed Title", url: picked)
        parsed.bookmarkData = Data([2])

        let relinked = ReimportMatcher.relink(original, to: parsed)

        XCTAssertEqual(relinked.url, stored)
        XCTAssertEqual(relinked.fileURL, picked)
        XCTAssertEqual(relinked.title, "Stored Title")
        XCTAssertEqual(relinked.currentTime, 120)
        XCTAssertEqual(relinked.bookmarkData, Data([2]))
    }

    // MARK: - isSameFile, on real files

    func test_isSameFile_onRealFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReimportMatcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("book.m4b")
        try Data([1, 2, 3]).write(to: file)
        let hardLink = directory.appendingPathComponent("link.m4b")
        try FileManager.default.linkItem(at: file, to: hardLink)
        let copy = directory.appendingPathComponent("copy.m4b")
        try FileManager.default.copyItem(at: file, to: copy)
        let spelledDifferently = directory.appendingPathComponent("./sub/../book.m4b")

        XCTAssertTrue(ReimportMatcher.isSameFile(file, spelledDifferently))
        XCTAssertTrue(ReimportMatcher.isSameFile(file, hardLink), "one file, two names")
        XCTAssertFalse(ReimportMatcher.isSameFile(file, copy))
        XCTAssertFalse(ReimportMatcher.isSameFile(file, directory.appendingPathComponent("gone.m4b")))
    }
}

/// `FileLoader` over fakes of the library (#208): a lost book's file, picked from its new place,
/// is saved back to the book's own row (new bookmark, same identity and position) and adds none.
/// Nothing reads or writes the app's real Core Data store, so what the simulator's library holds
/// can't change the outcome.
final class FileLoaderReimportTests: XCTestCase {
    /// Where the row was saved: no file there any more.
    private let storedURL = URL(fileURLWithPath: "/reimport-tests/gone/Moved.m4b")
    private var directory: URL?
    private var library = MockLoadAllAudiosUseCase()
    private var saver = MockSaveAudioUseCase()

    override func setUpWithError() throws {
        try super.setUpWithError()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileLoaderReimportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
        library = MockLoadAllAudiosUseCase()
        saver = MockSaveAudioUseCase()
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    func test_reimportingALostBooksFile_updatesItsRow_andAddsNone() async throws {
        insertLostBook(currentTime: 300)
        let picked = try placeFixture(named: "Moved.m4b")

        let result = await makeLoader().load(urls: [picked])

        let loaded = try XCTUnwrap(result.loaded.first)
        XCTAssertEqual(result.loaded.count, 1)
        XCTAssertEqual(loaded.url, storedURL, "the book it already was")
        XCTAssertEqual(loaded.fileURL, picked, "opens the file where it is now")
        XCTAssertEqual(loaded.currentTime, 300, "the position is kept")
        XCTAssertEqual(saver.savedModels.count, 1)
        XCTAssertEqual(saver.savedModels.filter { $0.url == picked }.count, 0, "no second book")
        XCTAssertEqual(saver.savedModels.filter { $0.url == storedURL }.count, 1)
        XCTAssertNotNil(saver.savedModels.first?.bookmarkData, "the row now has a bookmark to the picked file")
    }

    func test_importingAnUnrelatedFile_stillAddsABook() async throws {
        insertLostBook(currentTime: 0, duration: 10)
        let picked = try placeFixture(named: "Another.m4b")

        let result = await makeLoader().load(urls: [picked])

        XCTAssertEqual(result.loaded.first?.url, picked)
        XCTAssertEqual(saver.savedModels.map(\.url), [picked])
        XCTAssertFalse(saver.savedModels.contains { $0.url == storedURL }, "the lost book is untouched")
    }

    // MARK: - Helpers

    private func makeLoader() -> FileLoader {
        // The picked URL is not a stored book's, so the file is parsed and matched against the library.
        FileLoader(
            loadAudioUseCase: MockLoadAudioUseCase(),
            saveAudioUseCase: saver,
            loadAllAudiosUseCase: library
        )
    }

    private func placeFixture(named name: String) throws -> URL {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Christmastide", withExtension: "m4b"))
        let url = try XCTUnwrap(directory).appendingPathComponent(name)
        try FileManager.default.copyItem(at: fixture, to: url)
        return url
    }

    /// The fixture's duration by default, as the book's was when it was imported.
    private func insertLostBook(currentTime: Double, duration: Double = 831.6) {
        var audio = AudioModel()
        audio.title = "Lost Book"
        audio.duration = duration
        audio.currentTime = currentTime
        audio.url = storedURL
        library.stub = [audio]
    }
}
