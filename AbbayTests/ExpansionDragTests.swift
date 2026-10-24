//
//  ExpansionDragTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The drag bookkeeping of the expansion. `DragGesture` doesn't call `onEnded` when the system
/// cancels a gesture (an incoming call, say), so a drag must notice a new gesture by its start
/// location, a presentation that moved on without it, and a reset with no end.
@MainActor
final class ExpansionDragTests: XCTestCase {
    private let barFrame = CGRect(x: 21, y: 743, width: 360, height: 48)
    private let screen = CGSize(width: 402, height: 874)
    private let first = CGPoint(x: 200, y: 60)
    private let second = CGPoint(x: 180, y: 70)

    private func openPresentation() -> PlayerPresentation {
        let book = ViewModelSupport.chaptered()
        let state = PlaybackState()
        state.setLoadedBook(book)
        let sut = PlayerPresentation(playback: state)
        sut.reportScreenSize(screen)
        sut.reportBarFrame(barFrame, screenHeight: screen.height)
        sut.open(book, animated: false)
        return sut
    }

    private func move(_ drag: ExpansionDrag, _ translationY: CGFloat, at start: CGPoint, _ presentation: PlayerPresentation) {
        drag.changed(translationY: translationY, startLocation: start, presentation: presentation, book: nil)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - A new gesture after a cancelled one

    /// The cancelled drag left its start behind; the next gesture (another start location) must
    /// begin a new interaction from what is on screen, not jump by the stale origin.
    func test_newStartLocation_restartsTheInteraction() {
        let presentation = openPresentation()
        let drag = ExpansionDrag()
        move(drag, 20, at: first, presentation)
        move(drag, 20 + 0.3 * barFrame.minY, at: first, presentation)
        XCTAssertEqual(presentation.progress, 0.7, accuracy: 0.001)
        // No onEnded: the system cancelled it.

        move(drag, 15, at: second, presentation)

        XCTAssertEqual(presentation.progress, 0.7, accuracy: 0.001, "continues from the screen, no jump")
        move(drag, 15 + 0.1 * barFrame.minY, at: second, presentation)
        XCTAssertEqual(presentation.progress, 0.6, accuracy: 0.001)
    }

    /// The presentation closed or reopened without this drag (a tap, VoiceOver, a scene change):
    /// the next event starts a new interaction even from the same location.
    func test_interactionEndedElsewhere_restartsOnTheNextEvent() {
        let presentation = openPresentation()
        let drag = ExpansionDrag()
        move(drag, 20, at: first, presentation)
        move(drag, 20 + 0.4 * barFrame.minY, at: first, presentation)

        presentation.open(ViewModelSupport.chaptered(), animated: false)
        move(drag, 20 + 0.4 * barFrame.minY, at: first, presentation)

        XCTAssertEqual(presentation.progress, 1, "a new interaction from the settled-open screen")
    }

    // MARK: - A reset without an end

    func test_resetWithoutEnd_settlesOpenAboveTheThreshold() async {
        let presentation = openPresentation()
        let drag = ExpansionDrag()
        move(drag, 10, at: first, presentation)
        move(drag, 10 + 0.2 * barFrame.minY, at: first, presentation)

        drag.cancel(presentation: presentation)

        XCTAssertFalse(drag.isActive)
        XCTAssertEqual(presentation.progress, 1)
        await waitUntil { presentation.isFullyOpen }
        XCTAssertTrue(presentation.isFullyOpen)
    }

    func test_resetWithoutEnd_settlesClosedPastTheThreshold() async {
        let presentation = openPresentation()
        let drag = ExpansionDrag()
        move(drag, 10, at: first, presentation)
        move(drag, 10 + 0.6 * barFrame.minY, at: first, presentation)

        drag.cancel(presentation: presentation)

        XCTAssertEqual(presentation.progress, 0)
        await waitUntil { presentation.presentedBook == nil }
        XCTAssertNil(presentation.presentedBook)
    }

    /// The scene leaving `.active` settles whatever drag is in flight, wherever it started.
    func test_cancelInteractive_settlesTheActiveInteraction_andIgnoresNone() async {
        let presentation = openPresentation()
        presentation.cancelInteractive()
        XCTAssertTrue(presentation.isFullyOpen, "nothing in flight: nothing changes")

        let start = presentation.beginInteractive()
        XCTAssertNotNil(start)
        presentation.updateInteractive(0.9)
        presentation.cancelInteractive()

        await waitUntil { presentation.isFullyOpen }
        XCTAssertTrue(presentation.isFullyOpen)
    }

    /// The 18.5 flick whose last sample was stationary: reported 59 pt/s, but the last 60 ms say
    /// a flick, so it collapses (it read as a slow release and settled back open before).
    func test_flickWithAStationaryLastSample_stillCollapses() async {
        let presentation = openPresentation()
        let drag = ExpansionDrag()
        for (time, translation) in [(0.000, 47.0), (0.023, 103.3), (0.032, 158.7), (0.049, 201.3), (0.066, 202.7)] {
            drag.changed(
                translationY: translation,
                startLocation: first,
                presentation: presentation,
                book: nil,
                time: 1000 + time
            )
        }

        drag.ended(velocityY: 59, presentation: presentation)

        XCTAssertEqual(presentation.progress, 0)
        await waitUntil { presentation.presentedBook == nil }
        XCTAssertNil(presentation.presentedBook)
    }

    /// N1: a fast 20% collapse drag, a 500 ms hold with no events, then the lift: slow, so it
    /// settles back open (20% < 30%), not closed as a flick.
    func test_fastDragThenHold_settlesByDistance() async {
        let presentation = openPresentation()
        let drag = ExpansionDrag()
        let travel = barFrame.minY
        for (time, share) in [(0.000, 0.0), (0.016, 0.07), (0.033, 0.14), (0.050, 0.2)] {
            drag.changed(
                translationY: 10 + share * travel,
                startLocation: first,
                presentation: presentation,
                book: nil,
                time: 1000 + time
            )
        }

        drag.ended(velocityY: 3, presentation: presentation, time: 1000.550)

        XCTAssertEqual(presentation.progress, 1, "a held finger is a slow release")
        await waitUntil { presentation.isFullyOpen }
        XCTAssertTrue(presentation.isFullyOpen)
    }

    // MARK: - The bar's axis

    /// The bar's axis is decided once per gesture; a new start location is a new gesture, so a
    /// cancelled vertical drag doesn't turn the next horizontal swipe into an expansion.
    func test_barAxis_isDecidedAgainForANewGesture() {
        let drag = BarDrag()

        XCTAssertEqual(drag.axis(for: CGSize(width: 2, height: -14), startLocation: first), .vertical)
        XCTAssertEqual(drag.axis(for: CGSize(width: 40, height: -10), startLocation: first), .vertical, "same gesture")
        XCTAssertEqual(drag.axis(for: CGSize(width: -14, height: 2), startLocation: second), .horizontal)
    }

    // MARK: - Collapse from the chapter list (iOS 18+)

    func test_listCollapse_engagesOnlyAtTheTop_andDownward() {
        let presentation = openPresentation()
        let list = ExpansionListCollapse(presentation: presentation)

        list.listOffset = 120
        list.changed(translation: CGSize(width: 0, height: 60), startLocation: first)
        XCTAssertFalse(list.isEngaged, "scrolled down: the list scrolls")
        XCTAssertEqual(presentation.progress, 1)
        list.ended(velocityY: 0)

        list.listOffset = 0
        list.changed(translation: CGSize(width: 0, height: -60), startLocation: second)
        XCTAssertFalse(list.isEngaged, "upward at the top scrolls the list")
        list.ended(velocityY: 0)

        let third = CGPoint(x: 150, y: 400)
        list.changed(translation: CGSize(width: 2, height: 12), startLocation: third)
        XCTAssertTrue(list.isEngaged)
        list.changed(translation: CGSize(width: 2, height: 12 + 0.2 * barFrame.minY), startLocation: third)
        XCTAssertEqual(presentation.progress, 0.8, accuracy: 0.001)
        list.ended(velocityY: 0)
        XCTAssertFalse(list.isEngaged)
    }

    func test_listCollapse_decidesOncePerGesture() {
        let presentation = openPresentation()
        let list = ExpansionListCollapse(presentation: presentation)
        list.listOffset = 80

        list.changed(translation: CGSize(width: 0, height: 20), startLocation: first)
        // The list reaches its top mid-gesture: still scrolling, never a collapse.
        list.listOffset = 0
        list.changed(translation: CGSize(width: 0, height: 200), startLocation: first)

        XCTAssertFalse(list.isEngaged)
        XCTAssertEqual(presentation.progress, 1)
    }
}
