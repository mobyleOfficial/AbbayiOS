//
//  PlayerRedesignTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The pure decisions of the redesigned player (#166 G1 + G2): the scrubber's labels, the
/// subtitle, the chapter panel's place and progress, and the one-check rule of #225.
final class PlayerRedesignTests: XCTestCase {
    // MARK: - Scrubber

    func test_scrubberFraction_clampsAndSurvivesAZeroTotal() {
        XCTAssertEqual(PlayerProgressView.fraction(current: 30, total: 120), 0.25)
        XCTAssertEqual(PlayerProgressView.fraction(current: 200, total: 120), 1)
        XCTAssertEqual(PlayerProgressView.fraction(current: -5, total: 120), 0)
        XCTAssertEqual(PlayerProgressView.fraction(current: 30, total: 0), 0)
        XCTAssertEqual(PlayerProgressView.fraction(current: .nan, total: 120), 0)
    }

    func test_scrubberTimes_areCompact() {
        XCTAssertEqual(PlayerProgressView.clockText(1032), "17:12")
        XCTAssertEqual(PlayerProgressView.clockText(5), "0:05")
        XCTAssertEqual(PlayerProgressView.clockText(3909), "1:05:09")
        XCTAssertEqual(PlayerProgressView.clockText(.infinity), "0:00")
    }

    func test_remainingText_hasAMinusSign_andNeverGoesNegative() {
        XCTAssertEqual(PlayerProgressView.remainingText(current: 1032, total: 2719), "\u{2212}28:07")
        XCTAssertEqual(PlayerProgressView.remainingText(current: 3000, total: 2719), "\u{2212}0:00")
    }

    // MARK: - Subtitle

    func test_subtitle_isAuthorAndChapterPosition() {
        let text = PlayerSubtitle.text(author: "Arthur Conan Doyle", chapter: 2, chapterCount: 12)
        XCTAssertEqual(text, "Arthur Conan Doyle · Ch 3 of 12")
    }

    func test_subtitle_withoutChapters_isTheAuthorAlone() {
        XCTAssertEqual(PlayerSubtitle.text(author: "Seed Author", chapter: 0, chapterCount: 0), "Seed Author")
    }

    func test_subtitle_withoutAuthor_isThePosition_clampedToTheBook() {
        XCTAssertEqual(PlayerSubtitle.text(author: "", chapter: 9, chapterCount: 3), "Ch 3 of 3")
        XCTAssertEqual(PlayerSubtitle.text(author: "", chapter: 0, chapterCount: 0), "")
    }

    // MARK: - Chapter panel

    func test_panel_sitsAbovePills_atItsIdealHeight_onATallScreen() {
        let frame = ChaptersPanelLayout.frame(
            container: CGSize(width: 402, height: 780),
            pillsTop: 720,
            idealHeight: ChaptersPanelLayout.idealHeight
        )

        XCTAssertEqual(frame.maxY, 720 - ChaptersPanelLayout.gap)
        XCTAssertEqual(frame.height, ChaptersPanelLayout.idealHeight)
        XCTAssertEqual(frame.minX, ChaptersPanelLayout.leadingInset)
        XCTAssertEqual(frame.maxX, 402 - ChaptersPanelLayout.trailingInset)
    }

    /// #203: on a short screen (the iPhone SE, the iOS 27.1 iPhone Duo at 678 pt) the panel still
    /// gets at least the chapter list's least height, and never runs above the screen's top.
    func test_panel_onAShortScreen_keepsAUsableHeight_andStaysOnScreen() {
        for height in [CGFloat(560), 603, 678] {
            let pillsTop = height - 60
            let frame = ChaptersPanelLayout.frame(
                container: CGSize(width: 375, height: height),
                pillsTop: pillsTop,
                idealHeight: ChaptersPanelLayout.idealHeight
            )
            XCTAssertGreaterThanOrEqual(frame.height, PlayerView.minChapterListHeight, "at \(height) pt")
            XCTAssertGreaterThanOrEqual(frame.minY, ChaptersPanelLayout.gap - 0.5, "at \(height) pt")
        }
    }

    func test_panel_beforeThePillsReport_assumesTheBottom() {
        let frame = ChaptersPanelLayout.frame(container: CGSize(width: 402, height: 700), pillsTop: 0, idealHeight: 440)

        XCTAssertEqual(frame.maxY, 700 - ChaptersPanelLayout.gap)
    }

    func test_chapterProgress_isTheShareOfTheCurrentChapter_inWholePercents() {
        let chapters = [
            ChapterModel(title: "One", startTime: 0, duration: 100),
            ChapterModel(title: "Two", startTime: 100, duration: 300)
        ]

        XCTAssertEqual(ChaptersPanel.chapterProgress(chapters: chapters, index: 1, time: 214.9), 0.38)
        XCTAssertEqual(ChaptersPanel.chapterProgress(chapters: chapters, index: 1, time: 50), 0)
        XCTAssertEqual(ChaptersPanel.chapterProgress(chapters: chapters, index: 1, time: 900), 1)
        XCTAssertNil(ChaptersPanel.chapterProgress(chapters: chapters, index: 5, time: 50))
        XCTAssertNil(ChaptersPanel.chapterProgress(chapters: [], index: 0, time: 0))
    }

    func test_dragClosesThePanel_onlyFromItsTop_downward() {
        let top = ChaptersPanel.dragHandleHeight - 1

        func closes(_ startY: CGFloat, _ dx: CGFloat, _ dy: CGFloat) -> Bool {
            ChaptersPanel.closesOnDrag(startY: startY, translation: CGSize(width: dx, height: dy))
        }

        XCTAssertTrue(closes(top, 4, 80))
        XCTAssertFalse(closes(200, 0, 120), "a drag on the list scrolls it")
        XCTAssertFalse(closes(top, 0, 20), "too short")
        XCTAssertFalse(closes(top, 0, -80), "upward")
        XCTAssertFalse(closes(top, 120, 60), "sideways")
    }

    // MARK: - #225: one check on a finished, downloaded chapter

    func test_finishedDownloadedChapter_showsNoDownloadCheck() {
        let state = BookDownloadState(
            chapters: [.downloaded, .failed, .downloaded, .downloading(fraction: 0.5)],
            isPaused: false,
            fraction: 0.6
        )

        XCTAssertNil(ChapterListView.shownStatus(at: 0, in: state, rowState: .finished))
        let failed = ChapterListView.shownStatus(at: 1, in: state, rowState: .finished)
        XCTAssertEqual(failed, .failed, "a failed chapter keeps its retry, finished or not")
        XCTAssertEqual(ChapterListView.shownStatus(at: 2, in: state, rowState: .current), .downloaded)
        let downloading = ChapterListView.shownStatus(at: 3, in: state, rowState: .upcoming)
        XCTAssertEqual(downloading, .downloading(fraction: 0.5))
        XCTAssertNil(ChapterListView.shownStatus(at: 9, in: state, rowState: .upcoming))
    }

    // MARK: - Seed

    func test_seedCoverArt_givesOnlyTheChosenBooksACover() {
        let books = UITestSeeder.seedModels().map(UITestSeeder.withCoverArt)

        let chaptered = books.first { $0.title == "Seeded Chaptered Book" }
        let plain = books.first { $0.title == "Seeded Plain Book" }
        XCTAssertNotNil(chaptered?.imageData.flatMap(UIImage.init(data:)))
        XCTAssertNil(plain?.imageData)
    }
}
