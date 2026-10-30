//
//  ReadAlongStoreTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Transcripts are files under one root, one per book, named after the book's identity.
final class ReadAlongStoreTests: XCTestCase {
    private var root = URL(fileURLWithPath: NSTemporaryDirectory())
    private let bookURL = URL(fileURLWithPath: "/library/book.m4b")
    private let otherURL = URL(fileURLWithPath: "/library/moby.m4b")

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadAlongStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func transcript(_ language: String, word: String = "hello") -> ReadAlongTranscript {
        var transcript = ReadAlongTranscript(language: language)
        let line = ReadAlongLine(start: 0, end: 1, words: [ReadAlongWord(text: word, start: 0, end: 1)])
        transcript.add([line], covering: ReadAlongSpan(start: 0, end: 2))
        return transcript
    }

    private var files: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    }

    func test_saveThenLoad_roundTrips() {
        let sut = ReadAlongStore(root: root)
        let saved = transcript("en-US")

        sut.save(saved, bookURL: bookURL)

        XCTAssertEqual(sut.load(bookURL: bookURL), saved)
    }

    func test_load_ofABookNeverSaved_isNil() {
        XCTAssertNil(ReadAlongStore(root: root).load(bookURL: bookURL))
    }

    func test_twoBooks_doNotCollide() {
        let sut = ReadAlongStore(root: root)
        sut.save(transcript("en-US"), bookURL: bookURL)
        sut.save(transcript("pt-BR", word: "ola"), bookURL: otherURL)

        XCTAssertEqual(sut.load(bookURL: bookURL)?.language, "en-US")
        XCTAssertEqual(sut.load(bookURL: otherURL)?.language, "pt-BR")
    }

    func test_fileName_isTheSHA256OfTheBookURLWithoutAReadableName() throws {
        let sut = ReadAlongStore(root: root)
        sut.save(transcript("en-US"), bookURL: bookURL)
        sut.waitForPendingSaves()

        let name = try XCTUnwrap(files.first)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(name.hasSuffix(".json"))
        XCTAssertEqual(name.count, 64 + ".json".count)
        XCTAssertFalse(name.contains("book"))
    }

    func test_delete_removesOnlyThatBook() {
        let sut = ReadAlongStore(root: root)
        sut.save(transcript("en-US"), bookURL: bookURL)
        sut.save(transcript("pt-BR"), bookURL: otherURL)

        sut.delete(bookURL: bookURL)

        XCTAssertNil(sut.load(bookURL: bookURL))
        XCTAssertNotNil(sut.load(bookURL: otherURL))
    }

    func test_deleteAll_emptiesTheRoot() {
        let sut = ReadAlongStore(root: root)
        sut.save(transcript("en-US"), bookURL: bookURL)
        sut.save(transcript("pt-BR"), bookURL: otherURL)

        sut.deleteAll()

        XCTAssertTrue(files.isEmpty)
        XCTAssertNil(sut.load(bookURL: bookURL))
    }

    func test_deleteAll_beforeAnythingWasSaved_isHarmless() {
        ReadAlongStore(root: root).deleteAll()
        ReadAlongStore(root: root).delete(bookURL: bookURL)
    }

    func test_save_afterDeleteAll_worksAgain() {
        let sut = ReadAlongStore(root: root)
        sut.save(transcript("en-US"), bookURL: bookURL)
        sut.deleteAll()

        sut.save(transcript("pt-BR"), bookURL: bookURL)

        XCTAssertEqual(sut.load(bookURL: bookURL)?.language, "pt-BR")
    }

    func test_load_ofACorruptFile_isNilAndDeletesIt() throws {
        let sut = ReadAlongStore(root: root)
        sut.save(transcript("en-US"), bookURL: bookURL)
        sut.waitForPendingSaves()
        let name = try XCTUnwrap(files.first)
        try Data("not json".utf8).write(to: root.appendingPathComponent(name))

        XCTAssertNil(sut.load(bookURL: bookURL))
        XCTAssertTrue(files.isEmpty)
    }

    func test_root_isExcludedFromBackupAfterTheFirstSave() throws {
        let sut = ReadAlongStore(root: root)

        sut.save(transcript("en-US"), bookURL: bookURL)
        sut.waitForPendingSaves()

        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func test_root_staysExcludedAfterDeleteAllAndANewSave() throws {
        let sut = ReadAlongStore(root: root)
        sut.save(transcript("en-US"), bookURL: bookURL)
        sut.deleteAll()

        sut.save(transcript("en-US"), bookURL: bookURL)
        sut.waitForPendingSaves()

        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    // MARK: - Off the main thread

    /// The session saves every couple of seconds from the main thread: the encoding and the write
    /// happen on the store's queue, so `save` returns at once.
    func test_save_returnsBeforeWriting_andTheWriteFollows() {
        let sut = ReadAlongStore(root: root)
        var big = ReadAlongTranscript(language: "en-US")
        let lines = (0..<30_000).map { index in
            ReadAlongLine(start: Double(index), end: Double(index) + 1, words: [
                ReadAlongWord(text: "word", start: Double(index), end: Double(index) + 1)
            ])
        }
        big.add(lines, covering: ReadAlongSpan(start: 0, end: 30_000))

        sut.save(big, bookURL: bookURL)

        XCTAssertTrue(files.isEmpty, "save waited for the write")
        sut.waitForPendingSaves()
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(sut.load(bookURL: bookURL), big)
    }

    func test_loadInBackground_readsWhatWasSaved() async {
        let sut = ReadAlongStore(root: root)
        sut.save(transcript("pt-BR"), bookURL: bookURL)

        let loaded = await sut.loadInBackground(bookURL: bookURL)
        let missing = await sut.loadInBackground(bookURL: otherURL)

        XCTAssertEqual(loaded.transcript, transcript("pt-BR"))
        XCTAssertNil(missing.transcript)
    }

    // MARK: - A book deleted while its text is shown

    /// A session keeps the stamp it loaded with; once the book is deleted, its saves are dropped, so
    /// it can't write the transcript back. A session that loads after the delete saves again.
    func test_save_stampedBeforeADelete_isDropped_andAFreshStampSaves() async {
        let sut = ReadAlongStore(root: root)
        sut.save(transcript("en-US"), bookURL: bookURL)
        let before = await sut.loadInBackground(bookURL: bookURL)
        let other = await sut.loadInBackground(bookURL: otherURL)

        sut.delete(bookURL: bookURL)
        sut.save(transcript("en-US", word: "back"), bookURL: bookURL, unlessDeletedSince: before.stamp)
        sut.save(transcript("pt-BR"), bookURL: otherURL, unlessDeletedSince: other.stamp)

        XCTAssertNil(sut.load(bookURL: bookURL), "the deleted book's text came back")
        XCTAssertEqual(sut.load(bookURL: otherURL)?.language, "pt-BR", "another book is unaffected")

        let after = await sut.loadInBackground(bookURL: bookURL)
        sut.save(transcript("en-US", word: "again"), bookURL: bookURL, unlessDeletedSince: after.stamp)
        XCTAssertEqual(sut.load(bookURL: bookURL), transcript("en-US", word: "again"))
    }
}
