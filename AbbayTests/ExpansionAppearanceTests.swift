//
//  ExpansionAppearanceTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// What the expansion draws at each progress (#162). With Reduce Motion it must cross-fade: the
/// panel full-screen with square corners and the cover where the details screen lays it out at
/// every progress, with only the panel's opacity moving. `ExpansionLayout` takes all of these
/// from `ExpansionMath`, so a regression that grows the frame again fails here.
///
/// Sampled at every 5% from 0 to 1, plus a spring's overshoot either side.
final class ExpansionAppearanceTests: XCTestCase {
    private let screen = CGSize(width: 402, height: 874)
    /// The hand-built dock on iOS 18 (the accessory is similar, with a capsule's radius).
    private let bar = CGRect(x: 8, y: 735, width: 386, height: 56)
    private let startRadius: CGFloat = 8
    /// The details screen's cover, as `ExpansionGeometry` reports it.
    private let target = CGRect(x: 41, y: 103, width: 320, height: 320)
    private let barSlot = CGRect(x: 8, y: 8, width: 40, height: 40)

    private var fullScreen: CGRect { CGRect(origin: .zero, size: screen) }
    private var samples: [CGFloat] { (0...20).map { CGFloat($0) / 20 } }

    private func appearance(_ progress: CGFloat, reduceMotion: Bool) -> ExpansionAppearance {
        ExpansionMath.appearance(
            progress: progress,
            startFrame: bar,
            screen: screen,
            startRadius: startRadius,
            reduceMotion: reduceMotion
        )
    }

    private func coverFrame(_ progress: CGFloat, reduceMotion: Bool) -> CGRect {
        ExpansionMath.coverFrame(
            progress: progress,
            barSlot: barSlot,
            target: target,
            panelFrame: appearance(progress, reduceMotion: reduceMotion).panelFrame,
            reduceMotion: reduceMotion
        )
    }

    // MARK: - Reduce Motion

    func test_reduceMotion_panelIsFullScreenWithSquareCorners_atEveryProgress() {
        for progress in samples + [-0.1, 1.1] {
            let look = appearance(progress, reduceMotion: true)
            XCTAssertEqual(look.panelFrame, fullScreen, "the frame moved at \(progress)")
            XCTAssertEqual(look.cornerRadius, 0, "the corners moved at \(progress)")
        }
    }

    /// Only the opacity moves, and it is the progress: 0 closed, 1 open.
    func test_reduceMotion_onlyThePanelsOpacityMoves() {
        for progress in samples {
            let look = appearance(progress, reduceMotion: true)
            XCTAssertEqual(look.panelOpacity, progress, accuracy: 0.0001)
            XCTAssertEqual(look.barContentOpacity, 0, "the bar's face shows inside the panel at \(progress)")
            XCTAssertEqual(look.detailsOpacity, 1, "the details screen fades on its own at \(progress)")
        }
        XCTAssertEqual(appearance(-0.1, reduceMotion: true).panelOpacity, 0, "an overshoot below 0 is clamped")
        XCTAssertEqual(appearance(1.1, reduceMotion: true).panelOpacity, 1, "an overshoot above 1 is clamped")
    }

    func test_reduceMotion_coverStaysWhereTheDetailsScreenLaysItOut() {
        for progress in samples {
            XCTAssertEqual(coverFrame(progress, reduceMotion: true), target, "the cover moved at \(progress)")
            XCTAssertEqual(
                ExpansionMath.coverRadius(progress: progress, from: 4, to: 12, reduceMotion: true),
                12,
                "the cover's corners moved at \(progress)"
            )
        }
    }

    // MARK: - Without Reduce Motion

    /// The control: the same samples do grow the panel from the bar, so the checks above would
    /// see an interpolated frame.
    func test_withoutReduceMotion_panelGrowsFromTheBar_andStaysOpaque() {
        XCTAssertEqual(appearance(0, reduceMotion: false).panelFrame, bar)
        XCTAssertEqual(appearance(0, reduceMotion: false).cornerRadius, startRadius)
        XCTAssertEqual(appearance(1, reduceMotion: false).panelFrame, fullScreen)
        let middle = appearance(0.5, reduceMotion: false)
        XCTAssertEqual(middle.panelFrame, ExpansionMath.interpolate(bar, fullScreen, 0.5))
        XCTAssertNotEqual(middle.panelFrame, fullScreen)
        XCTAssertEqual(middle.cornerRadius, 4)
        for progress in samples {
            XCTAssertEqual(appearance(progress, reduceMotion: false).panelOpacity, 1)
        }
    }

    func test_withoutReduceMotion_fadesSplitAtThirtyPercent() {
        let early = appearance(0.15, reduceMotion: false)
        XCTAssertEqual(early.barContentOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(early.detailsOpacity, 0)
        let late = appearance(0.65, reduceMotion: false)
        XCTAssertEqual(late.barContentOpacity, 0)
        XCTAssertEqual(late.detailsOpacity, 0.5, accuracy: 0.0001)
    }

    /// From the bar's slot (riding with the panel) to the details screen's cover.
    func test_withoutReduceMotion_coverGrowsFromTheBarsSlot() {
        XCTAssertEqual(coverFrame(0, reduceMotion: false), barSlot.offsetBy(dx: bar.minX, dy: bar.minY))
        XCTAssertEqual(coverFrame(1, reduceMotion: false), target)
        XCTAssertNotEqual(coverFrame(0.5, reduceMotion: false), target)
        XCTAssertEqual(ExpansionMath.coverRadius(progress: 0.5, from: 4, to: 12, reduceMotion: false), 8)
    }

    // MARK: - The override

    /// `-forceReduceMotion` wins over the system setting; without it the system decides (#185).
    func test_reduceMotion_forcedValueWins_nilFollowsTheSystem() {
        XCTAssertTrue(ReduceMotion.resolve(system: false, forced: true))
        XCTAssertTrue(ReduceMotion.resolve(system: true, forced: nil))
        XCTAssertFalse(ReduceMotion.resolve(system: false, forced: nil))
    }
}
