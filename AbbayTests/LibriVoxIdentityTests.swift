//
//  LibriVoxIdentityTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

final class LibriVoxIdentityTests: XCTestCase {
    private var root = FileManager.default.temporaryDirectory

    private let chapter = ChapterModel(
        title: "One",
        startTime: 0,
        duration: 60,
        remoteURL: URL(string: "https://archive.org/download/wonderland/wonderland_ch_01_64kb.mp3")
    )

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func test_bookURL_usesLibriVoxScheme() {
        XCTAssertEqual(LibriVoxIdentity.bookURL(id: "200").absoluteString, "librivox://book/200")
    }

    func test_bookID_roundTrips() {
        XCTAssertEqual(LibriVoxIdentity.bookID(from: LibriVoxIdentity.bookURL(id: "200")), "200")
    }

    func test_bookID_isNilForOtherURLs() {
        XCTAssertNil(LibriVoxIdentity.bookID(from: URL(string: "file:///x.m4b")))
        XCTAssertNil(LibriVoxIdentity.bookID(from: nil))
    }

    func test_localFileURL_isInsideBookDirectory() throws {
        let url = try XCTUnwrap(LibriVoxIdentity.localFileURL(for: chapter, bookID: "200", root: root))
        XCTAssertTrue(url.path.hasSuffix("/200/wonderland_ch_01_64kb.mp3"))
        XCTAssertTrue(url.path.hasPrefix(root.path))
    }

    func test_localFileURL_isNilWithoutRemoteURL() {
        XCTAssertNil(LibriVoxIdentity.localFileURL(for: ChapterModel(), bookID: "200", root: root))
    }

    func test_localFileURL_isNilForAMalformedRemoteFileName() {
        // Each would otherwise resolve to the book directory or above it, which the download
        // manager's move deletes before replacing.
        let malformed = [
            "https://archive.org",
            "https://archive.org/",
            "https://archive.org/download/.",
            "https://archive.org/download/..",
            "https://archive.org/download/a%2Fb.mp3"
        ]
        for string in malformed {
            let chapter = ChapterModel(remoteURL: URL(string: string))
            XCTAssertNil(LibriVoxIdentity.localFileURL(for: chapter, bookID: "200", root: root), string)
            XCTAssertFalse(LibriVoxIdentity.isDownloaded(chapter, bookID: "200", root: root), string)
        }
    }

    func test_playableURL_streamsUntilDownloaded() throws {
        XCTAssertEqual(
            LibriVoxIdentity.playableURL(for: chapter, bookID: "200", root: root),
            chapter.remoteURL
        )
        XCTAssertFalse(LibriVoxIdentity.isDownloaded(chapter, bookID: "200", root: root))

        let local = try XCTUnwrap(LibriVoxIdentity.localFileURL(for: chapter, bookID: "200", root: root))
        _ = try LibriVoxIdentity.directory(forBookID: "200", root: root)
        try Data([1]).write(to: local)

        XCTAssertTrue(LibriVoxIdentity.isDownloaded(chapter, bookID: "200", root: root))
        XCTAssertEqual(LibriVoxIdentity.playableURL(for: chapter, bookID: "200", root: root), local)
    }

    func test_directory_isCreatedAndExcludedFromBackup() throws {
        let directory = try LibriVoxIdentity.directory(forBookID: "200", root: root)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    // MARK: - isFullyDownloaded (the "Downloaded" tag)

    private func book(chapters: [ChapterModel]? = nil) -> AudioModel {
        AudioModel(chapters: chapters ?? [chapter], url: LibriVoxIdentity.bookURL(id: "200"), librivoxID: "200")
    }

    func test_isFullyDownloaded_trueForCompleteTrackedState() {
        let state = BookDownloadState(chapters: [.downloaded], expectedBytes: [], isPaused: false)

        XCTAssertTrue(LibriVoxIdentity.isFullyDownloaded(book(), state: state, root: root))
    }

    func test_isFullyDownloaded_falseForIncompleteTrackedState_evenIfFileExists() throws {
        let local = try XCTUnwrap(LibriVoxIdentity.localFileURL(for: chapter, bookID: "200", root: root))
        try FileManager.default.createDirectory(
            at: local.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: local.path, contents: Data())
        let state = BookDownloadState(chapters: [.downloading(fraction: 0.5)], expectedBytes: [], isPaused: false)

        XCTAssertFalse(LibriVoxIdentity.isFullyDownloaded(book(), state: state, root: root))
    }

    func test_isFullyDownloaded_untrackedFollowsFilesOnDisk() throws {
        XCTAssertFalse(LibriVoxIdentity.isFullyDownloaded(book(), state: nil, root: root))

        let local = try XCTUnwrap(LibriVoxIdentity.localFileURL(for: chapter, bookID: "200", root: root))
        try FileManager.default.createDirectory(
            at: local.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: local.path, contents: Data())

        XCTAssertTrue(LibriVoxIdentity.isFullyDownloaded(book(), state: nil, root: root))
    }

    func test_isFullyDownloaded_falseWithoutChaptersOrForImportedBook() {
        XCTAssertFalse(LibriVoxIdentity.isFullyDownloaded(book(chapters: []), state: nil, root: root))
        XCTAssertFalse(LibriVoxIdentity.isFullyDownloaded(AudioModel(chapters: [chapter]), state: nil, root: root))
    }
}
