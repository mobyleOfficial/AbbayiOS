//
//  DownloadHousekeepingTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// "Delete finished downloads" selects books whose download is complete AND whose position is at
/// the end; the space used is the size of the LibriVox downloads directory.
final class DownloadHousekeepingTests: XCTestCase {
    private var root: URL?

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadHousekeepingTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func libriVoxBook(_ id: String, currentTime: Double, duration: Double = 200) -> AudioModel {
        AudioModel(
            title: id,
            duration: duration,
            currentTime: currentTime,
            chapters: [1, 2].map { number in
                ChapterModel(
                    title: "\(number)",
                    startTime: Double(number - 1) * 100,
                    duration: 100,
                    remoteURL: URL(string: "https://e.org/\(id)-\(number).mp3")
                )
            },
            url: LibriVoxIdentity.bookURL(id: id),
            librivoxID: id
        )
    }

    /// Writes every chapter's file, so the book is fully downloaded on disk.
    private func download(_ book: AudioModel, bytes: Int = 10) throws {
        let root = try XCTUnwrap(root)
        let id = try XCTUnwrap(book.librivoxID)
        _ = try LibriVoxIdentity.directory(forBookID: id, root: root)
        for chapter in book.chapters {
            let file = try XCTUnwrap(LibriVoxIdentity.localFileURL(for: chapter, bookID: id, root: root))
            try Data(repeating: 1, count: bytes).write(to: file)
        }
    }

    private func select(_ books: [AudioModel], state: [String: BookDownloadState] = [:]) throws -> [String] {
        let root = try XCTUnwrap(root)
        return DownloadHousekeeping.finishedDownloads(in: books, state: { state[$0] }, root: root).map(\.title)
    }

    // MARK: - Finished

    func test_isFinished_withinTheToleranceOfTheEnd() {
        XCTAssertTrue(DownloadHousekeeping.isFinished(libriVoxBook("a", currentTime: 200)))
        XCTAssertTrue(DownloadHousekeeping.isFinished(libriVoxBook("a", currentTime: 171)))
        XCTAssertFalse(DownloadHousekeeping.isFinished(libriVoxBook("a", currentTime: 150)))
        let noDuration = libriVoxBook("a", currentTime: 0, duration: 0)
        XCTAssertFalse(DownloadHousekeeping.isFinished(noDuration), "no duration, no end")
    }

    // MARK: - Selection

    func test_selects_downloadedAndFinished() throws {
        let book = libriVoxBook("done", currentTime: 199)
        try download(book)

        XCTAssertEqual(try select([book]), ["done"])
    }

    func test_skips_downloadedButUnfinished() throws {
        let book = libriVoxBook("reading", currentTime: 50)
        try download(book)

        XCTAssertEqual(try select([book]), [])
    }

    func test_skips_finishedButNotFullyDownloaded() throws {
        let book = libriVoxBook("streamed", currentTime: 200)

        XCTAssertEqual(try select([book]), [], "nothing on disk to delete")
    }

    /// A download still in progress is not complete, whatever is on disk.
    func test_skips_aBookWhoseTrackedDownloadIsIncomplete() throws {
        let book = libriVoxBook("partial", currentTime: 200)
        try download(book)
        let state = BookDownloadState(chapters: [.downloaded, .waiting], expectedBytes: [10, 10], isPaused: true)

        XCTAssertEqual(try select([book], state: ["partial": state]), [])
    }

    func test_skips_importedBooks() throws {
        let imported = AudioModel(title: "imported", duration: 100, currentTime: 100, url: URL(string: "file:///a.m4b"))

        XCTAssertEqual(try select([imported]), [])
    }

    // MARK: - Space used

    func test_bytesUsed_sumsEveryFileUnderTheRoot() throws {
        let root = try XCTUnwrap(root)
        try download(libriVoxBook("one", currentTime: 0), bytes: 1000)
        try download(libriVoxBook("two", currentTime: 0), bytes: 500)

        XCTAssertEqual(DownloadHousekeeping.bytesUsed(under: root), 3000)
    }

    func test_bytesUsed_isZeroWithoutDownloads() throws {
        XCTAssertEqual(DownloadHousekeeping.bytesUsed(under: try XCTUnwrap(root)), 0)
    }
}
