//
//  ChapterListViewTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The decisions behind the chapter list shared by the player sheet and the LibriVox page.
final class ChapterListViewTests: XCTestCase {
    private let partial = BookDownloadState(
        chapters: [.downloaded, .downloading(fraction: 0.4)],
        isPaused: false,
        fraction: 0.7
    )
    private let complete = BookDownloadState(chapters: [.downloaded, .downloaded], isPaused: false, fraction: 1)

    // MARK: - Items

    func test_item_fromChapterModel_keepsTitleAndDuration() {
        let item = ChapterListView.Item(ChapterModel(title: "One", startTime: 30, duration: 90))

        XCTAssertEqual(item, ChapterListView.Item(title: "One", duration: 90))
    }

    func test_item_fromLibriVoxSection_usesItsSeconds() {
        let section = LibriVoxBook.Section(title: "Two", seconds: 125, listenURL: URL(fileURLWithPath: "/2.mp3"))

        XCTAssertEqual(ChapterListView.Item(section), ChapterListView.Item(title: "Two", duration: 125))
    }

    // MARK: - Overall progress

    func test_showsProgress_onlyWhileTheDownloadIsIncomplete() {
        XCTAssertFalse(ChapterListView.showsProgress(nil))
        XCTAssertTrue(ChapterListView.showsProgress(partial))
        XCTAssertFalse(ChapterListView.showsProgress(complete))
    }

    // MARK: - Row status

    func test_status_readsTheRowsChapterState() {
        XCTAssertEqual(ChapterListView.status(at: 0, in: partial), .downloaded)
        XCTAssertEqual(ChapterListView.status(at: 1, in: partial), .downloading(fraction: 0.4))
    }

    func test_status_isNilWithoutDownloadStateOrPastItsChapters() {
        XCTAssertNil(ChapterListView.status(at: 0, in: nil))
        XCTAssertNil(ChapterListView.status(at: 2, in: partial))
        XCTAssertNil(ChapterListView.status(at: -1, in: partial))
    }
}
