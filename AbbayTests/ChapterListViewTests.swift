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

    // MARK: - Hold hint (#148, #171)

    func test_shownHold_onlyWhenHeldAndStillDownloading() {
        for hold in NetworkHold.allCases {
            XCTAssertEqual(ChapterListView.shownHold(partial, hold: hold), hold)
            XCTAssertNil(ChapterListView.shownHold(complete, hold: hold))
            XCTAssertNil(ChapterListView.shownHold(nil, hold: hold))
        }
        XCTAssertNil(ChapterListView.shownHold(partial, hold: nil))
    }

    /// Each hold has its own text and id on both screens; Low Data Mode keeps its #148 ids.
    func test_holds_haveDistinctTextsAndIdentifiers() {
        let holds = NetworkHold.allCases
        XCTAssertEqual(Set(holds.map(\.message)).count, holds.count)
        XCTAssertEqual(Set(holds.map(\.systemImage)).count, holds.count)
        XCTAssertEqual(
            holds.map(\.detailIdentifier),
            ["detail.cellularHold", "detail.hotspotHold", "detail.lowDataMode"]
        )
        XCTAssertEqual(
            holds.map(\.playerIdentifier),
            ["player.download.cellularHold", "player.download.hotspotHold", "player.download.lowDataMode"]
        )
    }

    // MARK: - Download ring (#171)

    func test_ringLabel_saysPaused_thePercent_orThePercentAndWhy() {
        let paused = BookDownloadState(chapters: [.downloaded, .waiting], isPaused: true, fraction: 0.5)

        XCTAssertEqual(DownloadRingView.label(state: partial, hold: nil), "Downloading, 70%")
        XCTAssertEqual(
            DownloadRingView.label(state: partial, hold: .cellular),
            "Downloading, 70%. Waiting for Wi-Fi: on cellular"
        )
        XCTAssertEqual(DownloadRingView.label(state: paused, hold: .cellular), "Paused")
    }

    func test_ringGlyph_isPlayWhenPaused_theHoldsWhenHeld_andNoneOtherwise() {
        let paused = BookDownloadState(chapters: [.downloaded, .waiting], isPaused: true, fraction: 0.5)

        XCTAssertNil(DownloadRingView.glyph(state: partial, hold: nil))
        XCTAssertEqual(DownloadRingView.glyph(state: partial, hold: .personalHotspot), "personalhotspot")
        XCTAssertEqual(DownloadRingView.glyph(state: paused, hold: .personalHotspot), "play.fill")
    }

    // MARK: - No chapters (#115)

    /// A book with no chapter markers (a plain MP3) says so instead of showing an empty list.
    func test_showsEmptyState_onlyWithNoChapters() {
        XCTAssertTrue(ChapterListView.showsEmptyState([]))
        XCTAssertFalse(ChapterListView.showsEmptyState([.init(title: "One", duration: 1)]))
    }

    // MARK: - Row status

    func test_status_readsTheRowsChapterState() {
        XCTAssertEqual(ChapterListView.status(at: 0, in: partial), .downloaded)
        XCTAssertEqual(ChapterListView.status(at: 1, in: partial), .downloading(fraction: 0.4))
    }

    func test_canRetry_onlyForAFailedChapterWithARetryAction() {
        let failed = BookDownloadState(chapters: [.failed, .waiting], expectedBytes: [1, 1], isPaused: false)

        XCTAssertTrue(ChapterListView.canRetry(at: 0, in: failed, hasRetryAction: true))
        XCTAssertFalse(ChapterListView.canRetry(at: 0, in: failed, hasRetryAction: false))
        XCTAssertFalse(ChapterListView.canRetry(at: 1, in: failed, hasRetryAction: true))
        XCTAssertFalse(ChapterListView.canRetry(at: 0, in: nil, hasRetryAction: true))
    }

    func test_fraction_countsAFailedChapterAsNotDownloaded() {
        let state = BookDownloadState(chapters: [.downloaded, .failed], expectedBytes: [1, 1], isPaused: false)

        XCTAssertEqual(state.fraction, 0.5)
        XCTAssertFalse(state.isComplete)
    }

    func test_status_isNilWithoutDownloadStateOrPastItsChapters() {
        XCTAssertNil(ChapterListView.status(at: 0, in: nil))
        XCTAssertNil(ChapterListView.status(at: 2, in: partial))
        XCTAssertNil(ChapterListView.status(at: -1, in: partial))
    }
}
