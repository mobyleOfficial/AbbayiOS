//
//  PlayerPresentationOriginTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Where `PlayerPresentation` grows the details screen from and lands it back (#241): the tapped
/// cover (a library cell, the Continue card) while it is on screen, else the bar, else the bottom
/// strip. The decision itself is `ExpansionMath.origin` (`ExpansionOriginTests`).
@MainActor
final class PlayerPresentationOriginTests: XCTestCase {
    private let other = AudioModel(title: "Other", url: URL(string: "file:///vm/other.m4b"))
    private let barFrame = CGRect(x: 21, y: 743, width: 360, height: 48)
    private let screen = CGSize(width: 402, height: 874)

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func loadedPresentation(_ book: AudioModel = ViewModelSupport.chaptered()) -> PlayerPresentation {
        let state = PlaybackState()
        state.setLoadedBook(book)
        let sut = PlayerPresentation(playback: state)
        sut.reportScreenSize(screen)
        sut.reportBarFrame(barFrame, screenHeight: screen.height)
        return sut
    }

    private let cellCover = ExpansionCover(frame: CGRect(x: 16, y: 420, width: 114, height: 114), cornerRadius: 10)

    /// A cell tap grows the player out of that cell's cover, even with the bar showing another book.
    func test_openFromACell_growsOutOfItsCover() {
        let sut = loadedPresentation()
        sut.reportSourceCover(cellCover, for: .cell(other))

        sut.open(other, animated: false, from: .cell(other))

        XCTAssertEqual(sut.origin, .cover(cellCover))
        XCTAssertEqual(sut.expansionStart, cellCover.frame)
    }

    func test_openFromTheContinueCard_growsOutOfItsCover() {
        let sut = PlayerPresentation(playback: PlaybackState())
        sut.reportScreenSize(screen)
        let card = ExpansionCover(frame: CGRect(x: 28, y: 190, width: 94, height: 94), cornerRadius: 8)
        sut.reportSourceCover(card, for: .continueCard(other))
        sut.reportSourceCover(cellCover, for: .cell(other))

        sut.open(other, animated: false, from: .continueCard(other))

        XCTAssertEqual(sut.origin, .cover(card), "the card's cover, not the same book's cell")
    }

    /// A source whose cover never reported (or is off screen) falls back to the bar, else the strip.
    func test_openFromACoverWithoutAFrame_fallsBackToTheBar_elseTheStrip() {
        let loaded = loadedPresentation()
        loaded.open(other, animated: false, from: .cell(other))
        XCTAssertEqual(loaded.origin, .bar(barFrame))

        let empty = PlayerPresentation(playback: PlaybackState())
        empty.reportScreenSize(screen)
        empty.open(other, animated: false, from: .cell(other))
        XCTAssertEqual(empty.origin, .bottomStrip)
    }

    /// The close lands on the cover again, at its latest frame (it can shift while the tab bar
    /// hides and comes back).
    func test_closeOpenedFromACell_landsOnTheCellsLatestFrame() async {
        let sut = loadedPresentation()
        sut.reportSourceCover(cellCover, for: .cell(other))
        sut.open(other, animated: false, from: .cell(other))
        let moved = ExpansionCover(frame: cellCover.frame.offsetBy(dx: 0, dy: 6), cornerRadius: 10)
        sut.reportSourceCover(moved, for: .cell(other))

        sut.close(animated: true)

        XCTAssertEqual(sut.origin, .cover(moved))
        await waitUntil { sut.presentedBook == nil }
        XCTAssertNil(sut.presentedBook)
    }

    /// The drag down does the same: it collapses toward the cover, with at least half the screen of
    /// travel so a cover near the top isn't hair-trigger.
    func test_collapseDragOpenedFromACover_landsOnTheCover() throws {
        let sut = loadedPresentation()
        let high = ExpansionCover(frame: CGRect(x: 16, y: 190, width: 94, height: 94), cornerRadius: 8)
        sut.reportSourceCover(high, for: .continueCard(other))
        sut.open(other, animated: false, from: .continueCard(other))

        let start = try XCTUnwrap(sut.beginInteractive())

        XCTAssertEqual(sut.origin, .cover(high))
        XCTAssertEqual(start.travel, screen.height / 2)
    }

    /// The cell left the screen while the player was open (it is gone, or scrolled away): the
    /// close lands on the bar instead.
    func test_closeAfterTheCellIsGone_landsOnTheBar() {
        let sut = loadedPresentation()
        sut.reportSourceCover(cellCover, for: .cell(other))
        sut.open(other, animated: false, from: .cell(other))
        sut.removeSourceCover(for: .cell(other))

        sut.close(animated: false)

        XCTAssertEqual(sut.origin, .bar(barFrame))
    }

    func test_closeAfterTheCellScrolledAway_withoutABar_landsOnTheStrip() {
        let sut = PlayerPresentation(playback: PlaybackState())
        sut.reportScreenSize(screen)
        sut.reportSourceCover(cellCover, for: .cell(other))
        sut.open(other, animated: false, from: .cell(other))
        sut.reportSourceCover(
            ExpansionCover(frame: cellCover.frame.offsetBy(dx: 0, dy: 1000), cornerRadius: 10),
            for: .cell(other)
        )

        sut.close(animated: false)

        XCTAssertEqual(sut.origin, .bottomStrip)
    }

    /// The next open from the bar grows from the bar, not from the cell of the last presentation.
    func test_openFromTheBarAfterACell_growsFromTheBar() throws {
        let book = ViewModelSupport.chaptered()
        let sut = loadedPresentation(book)
        sut.reportSourceCover(cellCover, for: .cell(other))
        sut.open(other, animated: false, from: .cell(other))
        sut.close(animated: false)

        sut.open(book, animated: false)
        XCTAssertEqual(sut.origin, .bar(barFrame))
        sut.close(animated: false)

        _ = try XCTUnwrap(sut.beginInteractive(book))
        XCTAssertEqual(sut.origin, .bar(barFrame), "a drag up from the bar")
    }
}
