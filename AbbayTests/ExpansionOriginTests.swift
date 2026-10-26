//
//  ExpansionOriginTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Where the player grows from and collapses back to (#241): the tapped cover while it is on
/// screen, else the mini player bar, else the bottom strip. And what the expansion draws when it
/// starts from a cover, with and without Reduce Motion.
final class ExpansionOriginTests: XCTestCase {
    private let screen = CGSize(width: 402, height: 874)
    private let bar = CGRect(x: 21, y: 743, width: 360, height: 48)
    /// A library cell's cover in the grid's second row.
    private let cell = ExpansionCover(frame: CGRect(x: 16, y: 420, width: 114, height: 114), cornerRadius: 10)
    private let target = CGRect(x: 41, y: 103, width: 320, height: 320)
    private var fullScreen: CGRect { CGRect(origin: .zero, size: screen) }

    private func coverFrame(_ progress: CGFloat, slot: CGRect, panel: CGRect) -> CGRect {
        ExpansionMath.coverFrame(
            progress: progress,
            barSlot: slot,
            target: target,
            panelFrame: panel,
            reduceMotion: false
        )
    }

    // MARK: - The decision

    func test_origin_aCoverOnScreen_winsOverTheBar() {
        XCTAssertEqual(ExpansionMath.origin(cover: cell, bar: bar, screen: screen), .cover(cell))
        XCTAssertEqual(ExpansionMath.origin(cover: cell, bar: nil, screen: screen), .cover(cell))
    }

    func test_origin_withoutACover_isTheBar_elseTheBottomStrip() {
        XCTAssertEqual(ExpansionMath.origin(cover: nil, bar: bar, screen: screen), .bar(bar))
        XCTAssertEqual(ExpansionMath.origin(cover: nil, bar: nil, screen: screen), .bottomStrip)
    }

    /// A cell scrolled away (or gone) is not somewhere to land: the close falls back to the bar.
    func test_origin_aCoverOffScreen_fallsBackToTheBar_thenTheStrip() {
        let scrolledAway = ExpansionCover(frame: cell.frame.offsetBy(dx: 0, dy: -500), cornerRadius: 10)
        let gone = ExpansionCover(frame: .zero, cornerRadius: 10)

        XCTAssertEqual(ExpansionMath.origin(cover: scrolledAway, bar: bar, screen: screen), .bar(bar))
        XCTAssertEqual(ExpansionMath.origin(cover: gone, bar: bar, screen: screen), .bar(bar))
        XCTAssertEqual(ExpansionMath.origin(cover: scrolledAway, bar: nil, screen: screen), .bottomStrip)
    }

    /// At least half the cover inside the window counts; less doesn't.
    func test_isOnScreen_needsHalfTheCover() {
        let side: CGFloat = 100
        let halfOut = CGRect(x: 0, y: -50, width: side, height: side)
        let mostlyOut = CGRect(x: 0, y: -51, width: side, height: side)

        XCTAssertTrue(ExpansionMath.isOnScreen(halfOut, screen: screen))
        XCTAssertFalse(ExpansionMath.isOnScreen(mostlyOut, screen: screen))
        XCTAssertFalse(ExpansionMath.isOnScreen(CGRect(x: 500, y: 10, width: side, height: side), screen: screen))
        XCTAssertFalse(ExpansionMath.isOnScreen(cell.frame, screen: .zero), "no window yet")
    }

    func test_origin_reportsItsFrameAndRadius() {
        XCTAssertEqual(ExpansionOrigin.cover(cell).frame, cell.frame)
        XCTAssertEqual(ExpansionOrigin.cover(cell).coverRadius, 10)
        XCTAssertEqual(ExpansionOrigin.bar(bar).frame, bar)
        XCTAssertNil(ExpansionOrigin.bar(bar).coverRadius)
        XCTAssertTrue(ExpansionOrigin.bar(bar).isBar)
        XCTAssertNil(ExpansionOrigin.bottomStrip.frame)
        XCTAssertFalse(ExpansionOrigin.cover(cell).isBar)
    }

    // MARK: - Travel

    /// From the start's top to the screen's top, but never less than half the screen.
    func test_travel_isAtLeastHalfTheScreen() {
        XCTAssertEqual(ExpansionMath.travel(startFrame: bar, screen: screen), bar.minY)
        XCTAssertEqual(ExpansionMath.travel(startFrame: cell.frame, screen: screen), screen.height / 2)
    }

    // MARK: - Drawing from a cover

    /// From a cover, the growing cover starts as the whole start frame, so at 0 it sits exactly on
    /// the cell's cover; from the bar it starts in the bar's cover slot.
    func test_coverSlot_fromACover_isTheWholeFrame() {
        let barSlot = CGRect(x: 12, y: 6, width: 36, height: 36)

        XCTAssertEqual(
            ExpansionMath.coverSlot(origin: .cover(cell), startFrame: cell.frame, barSlot: barSlot),
            CGRect(origin: .zero, size: cell.frame.size)
        )
        XCTAssertEqual(ExpansionMath.coverSlot(origin: .bar(bar), startFrame: bar, barSlot: barSlot), barSlot)
        XCTAssertEqual(ExpansionMath.coverSlot(origin: .bottomStrip, startFrame: bar, barSlot: barSlot), barSlot)
    }

    func test_fromACover_startsOnTheCell_andLandsOnTheDetailsCover() {
        let look = ExpansionMath.appearance(
            progress: 0,
            startFrame: cell.frame,
            screen: screen,
            startRadius: cell.cornerRadius,
            reduceMotion: false
        )
        let slot = ExpansionMath.coverSlot(origin: .cover(cell), startFrame: cell.frame, barSlot: .zero)

        XCTAssertEqual(look.panelFrame, cell.frame)
        XCTAssertEqual(look.cornerRadius, cell.cornerRadius)
        XCTAssertEqual(coverFrame(0, slot: slot, panel: look.panelFrame), cell.frame)
        let open = ExpansionMath.appearance(
            progress: 1, startFrame: cell.frame, screen: screen, startRadius: cell.cornerRadius, reduceMotion: false
        )
        XCTAssertEqual(open.panelFrame, fullScreen)
        XCTAssertEqual(coverFrame(1, slot: slot, panel: open.panelFrame), target)
    }

    /// Reduce Motion from a cover is the same cross-fade as from the bar: full screen, square
    /// corners, the cover already in place, only the opacity moving.
    func test_fromACover_reduceMotion_crossFades() {
        let slot = ExpansionMath.coverSlot(origin: .cover(cell), startFrame: cell.frame, barSlot: .zero)
        for step in 0...20 {
            let progress = CGFloat(step) / 20
            let look = ExpansionMath.appearance(
                progress: progress,
                startFrame: cell.frame,
                screen: screen,
                startRadius: cell.cornerRadius,
                reduceMotion: true
            )
            XCTAssertEqual(look.panelFrame, fullScreen, "the frame moved at \(progress)")
            XCTAssertEqual(look.cornerRadius, 0)
            XCTAssertEqual(look.panelOpacity, progress, accuracy: 0.0001)
            XCTAssertEqual(
                ExpansionMath.coverFrame(
                    progress: progress, barSlot: slot, target: target, panelFrame: look.panelFrame, reduceMotion: true
                ),
                target,
                "the cover moved at \(progress)"
            )
        }
    }
}
