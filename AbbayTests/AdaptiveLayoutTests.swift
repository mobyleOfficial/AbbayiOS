//
//  AdaptiveLayoutTests.swift
//  AbbayTests
//

@testable import Abbay
import SwiftUI
import XCTest

/// The adaptive layout's decisions (#255): the split, the library's columns, the bar's visibility,
/// and the presentation's semantic state across a split change. Sizes are points, as the app is
/// given them (inside the safe area); the device examples only name where such a size occurs.
@MainActor
final class AdaptiveLayoutTests: XCTestCase {
    // MARK: - Split

    private func decide(
        _ width: CGFloat,
        _ height: CGFloat,
        _ sizeClass: UserInterfaceSizeClass? = .regular,
        _ text: DynamicTypeSize = .large
    ) -> PaneLayout {
        AdaptiveLayout.decide(width: width, height: height, horizontalSizeClass: sizeClass, dynamicTypeSize: text)
    }

    func test_compactWidth_isOnePane_whateverTheSize() {
        // A phone in portrait, the folded iPhone Duo, a narrow iPad window.
        XCTAssertEqual(decide(402, 874, .compact), .single)
        XCTAssertEqual(decide(466, 678, .compact), .single)
        XCTAssertEqual(decide(1000, 900, .compact), .single, "a compact width is never split")
        XCTAssertEqual(decide(1000, 900, nil), .single)
    }

    func test_regularWidth_withRoomForBoth_isSplit() {
        // The unfolded iPhone Duo, an iPad in portrait and in landscape.
        let duo = decide(900, 640)
        XCTAssertTrue(duo.isSplit)
        let ipad = decide(820, 1140)
        XCTAssertEqual(ipad.playerWidth, AdaptiveLayout.minPlayerWidth, "a narrower pane is raised to the minimum")
        XCTAssertEqual(decide(1366, 1000).playerWidth, AdaptiveLayout.maxPlayerWidth, "the extra room goes to browsing")
    }

    func test_regularWidth_thatIsShortOrNarrow_isOnePane() {
        // A large phone in landscape: regular width, but too short for a player beside a grid.
        XCTAssertEqual(decide(870, 400), .single)
        XCTAssertEqual(decide(700, 1000), .single, "not enough width for both minimums")
    }

    func test_accessibilityText_needsMoreRoom() {
        XCTAssertTrue(decide(900, 640, .regular, .large).isSplit)
        XCTAssertEqual(decide(900, 640, .regular, .accessibility3), .single)
        XCTAssertTrue(decide(1200, 900, .regular, .accessibility3).isSplit)
    }

    func test_browsingKeepsItsMinimum_besideThePlayer() {
        for width in stride(from: CGFloat(700), through: 1400, by: 20) {
            guard let player = decide(width, 800).playerWidth else { continue }
            XCTAssertGreaterThanOrEqual(width - player, AdaptiveLayout.minBrowsingWidth, "at \(width)")
            XCTAssertGreaterThanOrEqual(player, AdaptiveLayout.minPlayerWidth, "at \(width)")
        }
    }

    // MARK: - Library columns

    private func columns(_ width: CGFloat, _ text: DynamicTypeSize = .large) -> Int {
        LibraryGridLayout.columnCount(width: width, dynamicTypeSize: text)
    }

    /// The grid is the window minus its 16 pt margins: a phone keeps the three columns it always
    /// had, and two from xLarge up.
    func test_phoneWidths_keepThreeColumns_andTwoAtLargeText() {
        XCTAssertEqual(columns(343), 3, "iPhone SE")
        XCTAssertEqual(columns(370), 3, "iPhone 17 Pro")
        XCTAssertEqual(columns(408), 3, "iPhone 17 Pro Max")
        XCTAssertEqual(columns(370, .xLarge), 2)
        XCTAssertEqual(columns(370, .xxxLarge), 2)
        XCTAssertEqual(columns(370, .accessibility2), 2)
    }

    /// #251: the folded iPhone Duo's grid is what is left beside its side strip; the columns follow
    /// that width, so none is cut off.
    func test_columnsFitTheGridsWidth() {
        for width in stride(from: CGFloat(200), through: 1400, by: 10) {
            let count = columns(width)
            let isWide = width > LibraryGridLayout.wideGridWidth
            let base = isWide ? LibraryGridLayout.wideCellWidth : LibraryGridLayout.minCellWidth
            let needed = CGFloat(count) * base + CGFloat(count - 1) * LibraryGridLayout.columnSpacing
            XCTAssertTrue(count == 1 || needed <= width, "\(count) columns don't fit \(width)")
        }
    }

    func test_wideGrids_showMoreAndLargerCovers() {
        XCTAssertEqual(columns(520), 4, "browsing beside the player on the unfolded Duo")
        XCTAssertEqual(columns(860), 5, "the unfolded Duo without the player")
        XCTAssertEqual(columns(1000), 6, "a full iPad")
    }

    /// #267: past the first row, a column change brings the top book back; in the first row the top
    /// of the library (Continue, the header) stays in view.
    func test_topBook_isRestoredOnlyPastTheFirstRow() {
        XCTAssertFalse(LibraryGridLayout.restoresTopBook(at: 0, oldColumnCount: 5))
        XCTAssertFalse(LibraryGridLayout.restoresTopBook(at: 4, oldColumnCount: 5))
        XCTAssertTrue(LibraryGridLayout.restoresTopBook(at: 5, oldColumnCount: 5))
        XCTAssertTrue(LibraryGridLayout.restoresTopBook(at: 3, oldColumnCount: 3))
    }

    func test_unmeasuredGrid_assumesAPhone() {
        XCTAssertEqual(columns(0), 3)
        XCTAssertEqual(columns(0, .xLarge), 2)
    }

    // MARK: - Mini player

    private let loaded = URL(string: "file:///vm/loaded.m4b")
    private let other = URL(string: "file:///vm/other.m4b")

    private func bar(_ loaded: URL?, _ presented: URL?, open: Bool, split: Bool) -> Bool {
        MiniPlayerVisibility.isShown(loaded: loaded, presented: presented, isFullyOpen: open, isSplit: split)
    }

    func test_bar_onePane_showsUntilThePlayerHasSettledOpen() {
        XCTAssertFalse(bar(nil, nil, open: false, split: false))
        XCTAssertTrue(bar(loaded, nil, open: false, split: false))
        XCTAssertFalse(bar(loaded, loaded, open: true, split: false))
    }

    func test_bar_split_hidesOnlyWhileThePaneShowsTheLoadedBook() {
        XCTAssertFalse(bar(nil, other, open: true, split: true))
        XCTAssertTrue(bar(loaded, nil, open: false, split: true))
        XCTAssertFalse(bar(loaded, loaded, open: true, split: true))
        XCTAssertTrue(
            bar(loaded, other, open: true, split: true),
            "a pane previewing another book leaves the loaded one in the bar"
        )
    }

    // MARK: - Presentation

    func test_split_openAndClose_areImmediate() {
        let sut = PlayerPresentation()
        sut.layoutChanged(usesPanes: true)

        sut.open(ViewModelSupport.chaptered(), animated: true)
        XCTAssertEqual(sut.progress, 1)
        XCTAssertTrue(sut.isFullyOpen)

        sut.close(animated: true)
        XCTAssertNil(sut.presentedBook, "the pane leaves at once")
        XCTAssertEqual(sut.progress, 0)
    }

    func test_chapters_openOnlyForAPresentedBookWithChapters() {
        let sut = PlayerPresentation()
        sut.setChapters(open: true)
        XCTAssertFalse(sut.isShowingChapters, "nothing presented")

        sut.open(AudioModel(title: "No chapters", url: other), animated: false)
        sut.setChapters(open: true)
        XCTAssertFalse(sut.isShowingChapters, "a book without chapters has none to show")

        sut.open(ViewModelSupport.chaptered(), animated: false)
        sut.setChapters(open: true)
        XCTAssertTrue(sut.isShowingChapters)
    }

    func test_chapters_closeWithThePlayer_andForAnotherBook() {
        let sut = PlayerPresentation()
        let book = ViewModelSupport.chaptered()
        sut.open(book, animated: false)
        sut.setChapters(open: true)

        sut.open(AudioModel(title: "Other", chapters: book.chapters, url: other), animated: false)
        XCTAssertFalse(sut.isShowingChapters, "another book's chapters are not this one's")

        sut.setChapters(open: true)
        sut.close(animated: false)
        XCTAssertFalse(sut.isShowingChapters)
    }

    /// A fold or a resize keeps what is open: the same book, its chapters, settled open in the
    /// new form.
    func test_layoutChange_keepsTheBookAndChapters() {
        let sut = PlayerPresentation()
        let book = ViewModelSupport.chaptered()
        sut.open(book, animated: false)
        sut.setChapters(open: true)

        sut.layoutChanged(usesPanes: true)
        XCTAssertEqual(sut.presentedBook?.url, book.url)
        XCTAssertTrue(sut.isShowingChapters)
        XCTAssertTrue(sut.isFullyOpen)

        sut.layoutChanged(usesPanes: false)
        XCTAssertEqual(sut.presentedBook?.url, book.url)
        XCTAssertTrue(sut.isShowingChapters)
        XCTAssertEqual(sut.progress, 1, "the full-screen player, settled open")
    }

    /// A split change mid-drag ends the drag and settles open: nothing is left aiming at the old
    /// layout.
    func test_layoutChange_midDrag_settlesOpen() {
        let sut = PlayerPresentation()
        let start = sut.beginInteractive(ViewModelSupport.chaptered())
        XCTAssertNotNil(start)
        sut.updateInteractive(0.4)

        sut.layoutChanged(usesPanes: true)

        XCTAssertFalse(sut.isInteracting(start?.id ?? -1))
        XCTAssertEqual(sut.progress, 1)
        XCTAssertTrue(sut.isFullyOpen)
    }

    func test_split_dragOnTheBar_opensThePane() {
        let sut = PlayerPresentation()
        sut.layoutChanged(usesPanes: true)
        let book = ViewModelSupport.chaptered()

        XCTAssertNil(sut.beginInteractive(book), "nothing to drag")
        XCTAssertEqual(sut.presentedBook?.url, book.url)
        XCTAssertTrue(sut.isFullyOpen)
    }
}
