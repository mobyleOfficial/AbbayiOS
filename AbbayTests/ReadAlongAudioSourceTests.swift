//
//  ReadAlongAudioSourceTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class ReadAlongAudioSourceTests: XCTestCase {
    private let bookID = "alice_in_wonderland_librivox"
    private var root = FileManager.default.temporaryDirectory

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func chapter(_ number: Int, start: Double, duration: Double) -> ChapterModel {
        ChapterModel(
            title: "Chapter \(number)",
            startTime: start,
            duration: duration,
            remoteURL: URL(string: "https://archive.org/download/wonderland/wonderland_ch_0\(number)_64kb.mp3")
        )
    }

    private func libriVoxBook() -> AudioModel {
        var book = AudioModel()
        book.librivoxID = bookID
        book.duration = 300
        book.chapters = [
            chapter(1, start: 0, duration: 100),
            chapter(2, start: 100, duration: 120),
            chapter(3, start: 220, duration: 80)
        ]
        return book
    }

    private func writeFile(for chapter: ChapterModel) throws -> URL {
        let url = try XCTUnwrap(LibriVoxIdentity.localFileURL(for: chapter, bookID: bookID, root: root))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: url)
        return url
    }

    private func importedBook() -> AudioModel {
        var book = AudioModel()
        book.url = URL(fileURLWithPath: "/tmp/imported-\(UUID().uuidString).m4b")
        book.duration = 500
        return book
    }

    func test_libriVox_mapsEachChapterToItsFile() throws {
        let book = libriVoxBook()
        let file = try writeFile(for: book.chapters[0])

        let source = ReadAlongAudioSource.make(for: book, root: root)

        XCTAssertTrue(source.isLibriVox)
        XCTAssertEqual(source.segments.map(\.bookStart), [0, 100, 220])
        XCTAssertEqual(source.segments.map(\.duration), [100, 120, 80])
        XCTAssertEqual(source.segments[0].fileURL, file)
        XCTAssertNil(source.segments[1].fileURL)
        XCTAssertNil(source.segments[2].fileURL)
        XCTAssertFalse(source.segments.contains { $0.isSecurityScoped })
    }

    func test_libriVox_isOnDeviceOnlyInsideDownloadedChapters() throws {
        let book = libriVoxBook()
        _ = try writeFile(for: book.chapters[0])

        let source = ReadAlongAudioSource.make(for: book, root: root)

        XCTAssertTrue(source.isOnDevice(at: 0))
        XCTAssertTrue(source.isOnDevice(at: 99.9))
        XCTAssertFalse(source.isOnDevice(at: 100))
        XCTAssertFalse(source.isOnDevice(at: 250))
    }

    func test_libriVox_withoutChaptersHasNoSegments() {
        var book = libriVoxBook()
        book.chapters = []

        let source = ReadAlongAudioSource.make(for: book, root: root)

        XCTAssertTrue(source.segments.isEmpty)
        XCTAssertNil(source.segment(at: 0))
        XCTAssertFalse(source.isOnDevice(at: 0))
    }

    func test_imported_isOneSegmentCoveringTheBook() {
        let book = importedBook()

        let source = ReadAlongAudioSource.make(for: book, root: root, fileExists: { _ in true })

        XCTAssertFalse(source.isLibriVox)
        XCTAssertEqual(source.segments.count, 1)
        XCTAssertEqual(source.segments[0].fileURL, book.fileURL)
        XCTAssertEqual(source.segments[0].bookStart, 0)
        XCTAssertEqual(source.segments[0].duration, book.duration)
        XCTAssertTrue(source.segments[0].isSecurityScoped)
        XCTAssertTrue(source.isOnDevice(at: 250))
    }

    func test_imported_usesTheResolvedURL() {
        var book = importedBook()
        let moved = URL(fileURLWithPath: "/tmp/moved-\(UUID().uuidString).m4b")
        book.resolvedURL = moved
        var checked: [URL] = []

        let source = ReadAlongAudioSource.make(for: book, root: root, fileExists: { checked.append($0); return true })

        XCTAssertEqual(source.segments[0].fileURL, moved)
        XCTAssertEqual(checked, [moved])
    }

    func test_imported_missingFileHasNoURL() {
        let source = ReadAlongAudioSource.make(for: importedBook(), root: root, fileExists: { _ in false })

        XCTAssertEqual(source.segments.count, 1)
        XCTAssertNil(source.segments[0].fileURL)
        XCTAssertFalse(source.isOnDevice(at: 10))
    }

    func test_segmentAt_clampsToTheEnds() throws {
        let book = libriVoxBook()
        _ = try writeFile(for: book.chapters[0])
        let source = ReadAlongAudioSource.make(for: book, root: root)

        XCTAssertEqual(source.segment(at: 100)?.bookStart, 100)
        XCTAssertEqual(source.segment(at: 219.9)?.bookStart, 100)
        XCTAssertEqual(source.segment(at: 9999)?.bookStart, 220)
        XCTAssertEqual(source.segment(at: -5)?.bookStart, 0)
    }

    func test_segmentAt_isNilWithoutSegments() {
        XCTAssertNil(ReadAlongAudioSource(segments: [], isLibriVox: false).segment(at: 0))
    }
}
