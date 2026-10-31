//
//  ExpansionMathTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The pure half of the mini player's expansion: how a drag maps to progress, when a release
/// settles open, when a collapse may start, and how the frames and fades interpolate.
final class ExpansionMathTests: XCTestCase {
    // MARK: - Progress

    func test_progress_dragUpIncreases() {
        XCTAssertEqual(ExpansionMath.progress(start: 0, translationY: -150, travel: 600), 0.25, accuracy: 0.0001)
    }

    func test_progress_dragDownFromOpenDecreases() {
        XCTAssertEqual(ExpansionMath.progress(start: 1, translationY: 300, travel: 600), 0.5, accuracy: 0.0001)
    }

    func test_progress_clampsToZeroAndOne() {
        XCTAssertEqual(ExpansionMath.progress(start: 0, translationY: 200, travel: 600), 0)
        XCTAssertEqual(ExpansionMath.progress(start: 0.5, translationY: -900, travel: 600), 1)
    }

    func test_progress_withoutTravel_keepsTheStart() {
        XCTAssertEqual(ExpansionMath.progress(start: 0.4, translationY: -100, travel: 0), 0.4)
    }

    // MARK: - Settling

    func test_shouldOpen_whileOpening() {
        XCTAssertTrue(ExpansionMath.shouldOpen(progress: 0.31, velocityY: 0, wasOpening: true))
        XCTAssertTrue(ExpansionMath.shouldOpen(progress: 0.10, velocityY: -900, wasOpening: true), "an upward flick")
        XCTAssertFalse(ExpansionMath.shouldOpen(progress: 0.29, velocityY: -100, wasOpening: true))
    }

    /// The same thresholds in reverse: a collapse past 30% of the travel, or a flick down, closes.
    func test_shouldOpen_whileClosing_isTheMirror() {
        XCTAssertFalse(ExpansionMath.shouldOpen(progress: 0.69, velocityY: 0, wasOpening: false))
        XCTAssertFalse(ExpansionMath.shouldOpen(progress: 0.95, velocityY: 900, wasOpening: false), "a downward flick")
        XCTAssertTrue(ExpansionMath.shouldOpen(progress: 0.71, velocityY: 100, wasOpening: false))
    }

    /// A flick of at least 800 pt/s decides by its own direction, even against the drag's (#130):
    /// pulled up past 30% then flicked down closes, pulled down past 30% then flicked up reopens.
    func test_shouldOpen_flickAgainstTheDrag_followsTheFlick() {
        XCTAssertFalse(ExpansionMath.shouldOpen(progress: 0.60, velocityY: 900, wasOpening: true))
        XCTAssertTrue(ExpansionMath.shouldOpen(progress: 0.40, velocityY: -900, wasOpening: false))
    }

    /// 800 pt/s itself is a flick; just under it the distance decides.
    func test_shouldOpen_flickBoundary_isInclusive() {
        XCTAssertFalse(ExpansionMath.shouldOpen(progress: 0.60, velocityY: 800, wasOpening: true))
        XCTAssertTrue(ExpansionMath.shouldOpen(progress: 0.60, velocityY: 799, wasOpening: true))
        XCTAssertTrue(ExpansionMath.shouldOpen(progress: 0.40, velocityY: -800, wasOpening: false))
        XCTAssertFalse(ExpansionMath.shouldOpen(progress: 0.40, velocityY: -799, wasOpening: false))
    }

    func test_thresholds_matchTheSpec() {
        XCTAssertEqual(ExpansionMath.openThreshold, 0.30)
        XCTAssertEqual(ExpansionMath.flickVelocity, 800)
    }

    /// The bar's drag: mostly vertical expands, mostly horizontal is a chapter swipe.
    func test_isVerticalDrag_splitsTheBarsDrag() {
        XCTAssertTrue(ExpansionMath.isVerticalDrag(CGSize(width: 5, height: -13)))
        XCTAssertTrue(ExpansionMath.isVerticalDrag(CGSize(width: -8, height: 12)))
        XCTAssertFalse(ExpansionMath.isVerticalDrag(CGSize(width: -13, height: 4)))
        XCTAssertFalse(ExpansionMath.isVerticalDrag(CGSize(width: 12, height: 12)))
    }

    // MARK: - Release velocity

    /// A synthesized (or hesitant) last sample can make the reported velocity near 0 on a flick:
    /// the release uses the faster of it and the last 60 ms of samples (seen on iOS 18.5).
    func test_releaseVelocity_recoversAFlickWithAStationaryLastSample() {
        let samples: [(time: TimeInterval, translationY: CGFloat)] = [
            (0.000, 47), (0.023, 103.3), (0.032, 158.7), (0.049, 201.3), (0.066, 202.7)
        ]

        let velocity = ExpansionMath.releaseVelocity(reported: 59, samples: samples)

        XCTAssertGreaterThan(velocity, ExpansionMath.flickVelocity)
    }

    /// A finger that stopped before lifting is a slow release, whatever came before.
    func test_releaseVelocity_keepsASlowStop() {
        let samples: [(time: TimeInterval, translationY: CGFloat)] = [
            (0.0, 0), (0.1, 150), (0.5, 151), (0.6, 151)
        ]

        XCTAssertEqual(ExpansionMath.releaseVelocity(reported: 5, samples: samples), 5)
    }

    /// N1: a real held finger sends no samples. Fast samples, then 500 ms of nothing, then the
    /// lift: the window must end at the release, so it's a slow release, not a flick.
    func test_releaseVelocity_heldFingerWithNoSamples_isSlow() {
        let samples: [(time: TimeInterval, translationY: CGFloat)] = [
            (0.000, 0), (0.016, 40), (0.033, 90), (0.050, 150)
        ]

        let velocity = ExpansionMath.releaseVelocity(reported: 3, samples: samples, releaseTime: 0.550)

        XCTAssertEqual(velocity, 3, "held for 500 ms before lifting")
    }

    func test_releaseVelocity_keepsTheReportedOneWhenFaster() {
        XCTAssertEqual(ExpansionMath.releaseVelocity(reported: -2000, samples: [(0, 0), (0.05, -20)]), -2000)
        XCTAssertEqual(ExpansionMath.releaseVelocity(reported: 300, samples: []), 300)
    }

    // MARK: - Interpolation

    func test_interpolate_midpoint() {
        let bar = CGRect(x: 20, y: 740, width: 360, height: 56)
        let screen = CGRect(x: 0, y: 0, width: 400, height: 880)

        let middle = ExpansionMath.interpolate(bar, screen, 0.5)

        XCTAssertEqual(middle, CGRect(x: 10, y: 370, width: 380, height: 468))
    }

    func test_interpolate_endsAreTheInputs() {
        let bar = CGRect(x: 20, y: 740, width: 360, height: 56)
        let screen = CGRect(x: 0, y: 0, width: 400, height: 880)

        XCTAssertEqual(ExpansionMath.interpolate(bar, screen, 0), bar)
        XCTAssertEqual(ExpansionMath.interpolate(bar, screen, 1), screen)
    }

    /// Without a visible bar, the expansion grows from a 56 pt strip along the bottom edge.
    func test_startFrame_withoutABar_isTheBottomStrip() {
        let size = CGSize(width: 402, height: 874)
        let bar = CGRect(x: 21, y: 743, width: 360, height: 48)

        XCTAssertEqual(ExpansionMath.startFrame(bar: nil, screen: size), CGRect(x: 0, y: 818, width: 402, height: 56))
        XCTAssertEqual(ExpansionMath.startFrame(bar: bar, screen: size), bar)
    }

    // MARK: - Fades

    /// The bar's content is gone by 30%, and the details screen fades in over the last 70%.
    func test_fades_splitAtThirtyPercent() {
        XCTAssertEqual(ExpansionMath.barContentOpacity(0), 1)
        XCTAssertEqual(ExpansionMath.barContentOpacity(0.15), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ExpansionMath.barContentOpacity(0.3), 0)
        XCTAssertEqual(ExpansionMath.barContentOpacity(0.8), 0)

        XCTAssertEqual(ExpansionMath.detailsOpacity(0.2), 0)
        XCTAssertEqual(ExpansionMath.detailsOpacity(0.3), 0)
        XCTAssertEqual(ExpansionMath.detailsOpacity(0.65), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ExpansionMath.detailsOpacity(1), 1)
    }

    func test_cornerRadius_goesFromTheBarsToZero() {
        XCTAssertEqual(ExpansionMath.cornerRadius(from: 8, progress: 0), 8)
        XCTAssertEqual(ExpansionMath.cornerRadius(from: 8, progress: 0.5), 4)
        XCTAssertEqual(ExpansionMath.cornerRadius(from: 8, progress: 1), 0)
    }

    // MARK: - Read-along square (#192)

    /// With the read-along text showing, the growing cover turns from the artwork into the text
    /// square's dark fill as it grows: all artwork at the bar, all square where it lands, so the
    /// hand-off to the real square is no swap (owner's device test).
    func test_textSquareBlend_isTheArtworkAtTheBarAndTheSquareWhereItLands() {
        XCTAssertEqual(ExpansionMath.textSquareBlend(progress: 0, reduceMotion: false), 0)
        XCTAssertEqual(ExpansionMath.textSquareBlend(progress: 1, reduceMotion: false), 1)
        XCTAssertEqual(ExpansionMath.textSquareBlend(progress: -0.1, reduceMotion: false), 0, "a spring's undershoot")
        XCTAssertEqual(ExpansionMath.textSquareBlend(progress: 1.1, reduceMotion: false), 1, "a spring's overshoot")
    }

    /// Over the growth, not at an end: no step, and always moving the same way.
    func test_textSquareBlend_crossFadesOverTheGrowth() {
        let middle = ExpansionMath.textSquareBlend(progress: 0.5, reduceMotion: false)
        XCTAssertGreaterThan(middle, 0.3)
        XCTAssertLessThan(middle, 0.7)
        var previous: CGFloat = 0
        for step in 0...100 {
            let value = ExpansionMath.textSquareBlend(progress: CGFloat(step) / 100, reduceMotion: false)
            XCTAssertGreaterThanOrEqual(value, previous, "goes back at \(step)%")
            XCTAssertLessThan(value - previous, 0.05, "jumps at \(step)%")
            previous = value
        }
    }

    /// Reduce Motion: nothing grows, the panel only fades, and the square is the square throughout.
    func test_textSquareBlend_withReduceMotion_isTheSquare() {
        for progress: CGFloat in [0, 0.3, 0.7, 1] {
            XCTAssertEqual(ExpansionMath.textSquareBlend(progress: progress, reduceMotion: true), 1)
        }
    }
}
