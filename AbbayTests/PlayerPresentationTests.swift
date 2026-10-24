//
//  PlayerPresentationTests.swift
//  AbbayTests
//

@testable import Abbay
import Observation
import XCTest

/// The one place that presents the details screen. A row tap, the bar and the details page's Play
/// all go through `open`, and `close` collapses it before letting go of the book.
@MainActor
final class PlayerPresentationTests: XCTestCase {
    private let other = AudioModel(title: "Other", url: URL(string: "file:///vm/other.m4b"))

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func test_startsClosed() {
        let sut = PlayerPresentation()

        XCTAssertNil(sut.presentedBook)
        XCTAssertEqual(sut.progress, 0)
    }

    func test_open_setsBookAndTargetsFullProgress() {
        let sut = PlayerPresentation()
        let book = ViewModelSupport.chaptered()

        sut.open(book, animated: true)

        XCTAssertEqual(sut.presentedBook?.url, book.url)
        XCTAssertEqual(sut.progress, 1)
    }

    func test_open_anotherBook_replacesThePresentedBook() {
        let sut = PlayerPresentation()
        sut.open(ViewModelSupport.chaptered(), animated: false)

        sut.open(other, animated: false)

        XCTAssertEqual(sut.presentedBook?.url, other.url)
        XCTAssertEqual(sut.progress, 1)
    }

    func test_close_clearsBookAfterCollapse() async {
        let sut = PlayerPresentation()
        sut.open(ViewModelSupport.chaptered(), animated: false)

        sut.close(animated: true)

        // The book stays while the collapse runs, so the screen doesn't empty mid-animation.
        XCTAssertEqual(sut.progress, 0)
        XCTAssertNotNil(sut.presentedBook)
        await waitUntil { sut.presentedBook == nil }
        XCTAssertNil(sut.presentedBook)
    }

    func test_close_notAnimated_clearsAtOnce() {
        let sut = PlayerPresentation()
        sut.open(ViewModelSupport.chaptered(), animated: false)

        sut.close(animated: false)

        XCTAssertNil(sut.presentedBook)
        XCTAssertEqual(sut.progress, 0)
    }

    /// Reopening during the collapse must not lose the book when the old collapse finishes.
    func test_openDuringCollapse_keepsTheNewBook() async throws {
        let sut = PlayerPresentation()
        sut.open(ViewModelSupport.chaptered(), animated: false)
        sut.close(animated: true)

        sut.open(other, animated: false)
        try await Task.sleep(for: .milliseconds(800))

        XCTAssertEqual(sut.presentedBook?.url, other.url)
        XCTAssertEqual(sut.progress, 1)
    }

    // MARK: - Settled open (hides the bar)

    /// The bar hides only once the details screen has settled open, and comes back as soon as a
    /// close starts, so it never pops out from under the growing screen.
    func test_isFullyOpen_followsTheSettledState() async {
        let sut = PlayerPresentation()
        XCTAssertFalse(sut.isFullyOpen)

        sut.open(ViewModelSupport.chaptered(), animated: true)
        XCTAssertFalse(sut.isFullyOpen, "still growing")
        await waitUntil { sut.isFullyOpen }
        XCTAssertTrue(sut.isFullyOpen)

        sut.close(animated: true)
        XCTAssertFalse(sut.isFullyOpen, "the bar comes back as the close starts")
    }

    func test_isFullyOpen_notAnimated_isImmediate() {
        let sut = PlayerPresentation()

        sut.open(ViewModelSupport.chaptered(), animated: false)
        XCTAssertTrue(sut.isFullyOpen)
        sut.close(animated: false)

        XCTAssertFalse(sut.isFullyOpen)
    }

    /// An open that is closed before it settles must not mark the closed screen as open.
    func test_closeBeforeOpenSettles_staysNotFullyOpen() async throws {
        let sut = PlayerPresentation()
        sut.open(ViewModelSupport.chaptered(), animated: true)

        sut.close(animated: true)
        try await Task.sleep(for: .milliseconds(800))

        XCTAssertFalse(sut.isFullyOpen)
    }

    // MARK: - Bar frame (where Task 8's expansion starts)

    func test_barFrame_ignoresFramesAwayFromTheBottom_andEqualValues() {
        let sut = PlayerPresentation()
        let screenHeight: CGFloat = 874
        let frame = CGRect(x: 21, y: 743, width: 360, height: 56)
        var fired = 0

        sut.reportBarFrame(frame, screenHeight: screenHeight)
        XCTAssertEqual(sut.barFrame, frame)
        withObservationTracking({ _ = sut.barFrame }, onChange: { fired += 1 })
        sut.reportBarFrame(frame, screenHeight: screenHeight)
        // The system can host the accessory twice; a copy near the top is not the bar.
        sut.reportBarFrame(CGRect(x: 0, y: 8, width: 234, height: 32), screenHeight: screenHeight)

        XCTAssertEqual(fired, 0)
        XCTAssertEqual(sut.barFrame, frame)
    }
    // MARK: - Interactive expansion (Task 8)

    private let barFrame = CGRect(x: 21, y: 743, width: 360, height: 48)
    private let screen = CGSize(width: 402, height: 874)

    private func loadedPresentation(_ book: AudioModel = ViewModelSupport.chaptered()) -> PlayerPresentation {
        let state = PlaybackState()
        state.setLoadedBook(book)
        let sut = PlayerPresentation(playback: state)
        sut.reportScreenSize(screen)
        sut.reportBarFrame(barFrame, screenHeight: screen.height)
        return sut
    }

    /// A drag up from the bar presents the loaded book and starts from the bar's frame, taken once:
    /// the bar moving afterwards (the accessory slides with the tab bar) doesn't move the start.
    func test_beginInteractive_fromTheBar_snapshotsTheBarFrame() throws {
        let book = ViewModelSupport.chaptered()
        let sut = loadedPresentation(book)

        let start = try XCTUnwrap(sut.beginInteractive(book))
        sut.reportBarFrame(barFrame.offsetBy(dx: 0, dy: 70), screenHeight: screen.height)

        XCTAssertEqual(sut.presentedBook?.url, book.url)
        XCTAssertEqual(start.progress, 0)
        XCTAssertEqual(start.travel, barFrame.minY, "the bar's top travels to the screen's top")
        XCTAssertEqual(sut.expansionStart, barFrame)
        XCTAssertFalse(sut.isFullyOpen)
    }

    func test_open_withoutALoadedBook_startsFromTheBottomEdge() {
        let sut = PlayerPresentation(playback: PlaybackState())
        sut.reportScreenSize(screen)
        sut.reportBarFrame(barFrame, screenHeight: screen.height)

        sut.open(other, animated: false)

        XCTAssertNil(sut.expansionStart, "no bar is visible: the 56 pt strip at the bottom edge")
    }

    func test_beginInteractive_withNothingToPresent_returnsNil() {
        let sut = PlayerPresentation()

        XCTAssertNil(sut.beginInteractive())
        XCTAssertNil(sut.presentedBook)
    }

    /// Dragging writes progress with no animation, and only when it changes.
    func test_updateInteractive_assignsOnlyOnChange() throws {
        let book = ViewModelSupport.chaptered()
        let sut = loadedPresentation(book)
        _ = try XCTUnwrap(sut.beginInteractive(book))
        sut.updateInteractive(0.4)
        var fired = 0

        withObservationTracking({ _ = sut.progress }, onChange: { fired += 1 })
        sut.updateInteractive(0.4)

        XCTAssertEqual(fired, 0)
        XCTAssertEqual(sut.progress, 0.4)
        sut.updateInteractive(1.4)
        XCTAssertEqual(sut.progress, 1, "clamped")
    }

    func test_endInteractive_open_settlesFullyOpen() async throws {
        let book = ViewModelSupport.chaptered()
        let sut = loadedPresentation(book)
        _ = try XCTUnwrap(sut.beginInteractive(book))
        sut.updateInteractive(0.45)

        sut.endInteractive(open: true)

        XCTAssertEqual(sut.progress, 1)
        await waitUntil { sut.isFullyOpen }
        XCTAssertTrue(sut.isFullyOpen)
    }

    /// The Task 7 carry: an interactive collapse goes through the close path, so the bar comes back
    /// as the collapse starts and the book is released once it lands.
    func test_interactiveCollapse_goesThroughTheClosePath() async throws {
        let book = ViewModelSupport.chaptered()
        let sut = loadedPresentation(book)
        sut.open(book, animated: false)
        XCTAssertTrue(sut.isFullyOpen)

        let start = try XCTUnwrap(sut.beginInteractive())
        XCTAssertEqual(start.progress, 1)
        XCTAssertFalse(sut.isFullyOpen, "the bar and the tab bar come back as the collapse starts")
        sut.updateInteractive(0.5)
        sut.endInteractive(open: false)

        XCTAssertEqual(sut.progress, 0)
        await waitUntil { sut.presentedBook == nil }
        XCTAssertNil(sut.presentedBook)
        XCTAssertFalse(sut.isFullyOpen)
    }

    /// A collapse released short of 30% settles back open, and the bar hides again.
    func test_cancelledCollapse_settlesOpenAgain() async throws {
        let book = ViewModelSupport.chaptered()
        let sut = loadedPresentation(book)
        sut.open(book, animated: false)

        _ = try XCTUnwrap(sut.beginInteractive())
        sut.updateInteractive(0.8)
        sut.endInteractive(open: true)

        await waitUntil { sut.isFullyOpen }
        XCTAssertTrue(sut.isFullyOpen)
        XCTAssertEqual(sut.presentedBook?.url, book.url)
    }

    /// The collapse lands where the expansion started: the bar's frame from before it hid.
    func test_collapse_keepsTheStartFromTheOpen() throws {
        let book = ViewModelSupport.chaptered()
        let sut = loadedPresentation(book)
        sut.open(book, animated: false)
        sut.reportBarFrame(barFrame.offsetBy(dx: 0, dy: 70), screenHeight: screen.height)

        _ = try XCTUnwrap(sut.beginInteractive())

        XCTAssertEqual(sut.expansionStart, barFrame)
    }

    /// Interruptible: grabbing mid-spring continues from what is on screen, not from the target,
    /// and the interrupted settle no longer completes.
    func test_grabMidSpring_continuesFromTheRenderedProgress() async throws {
        let book = ViewModelSupport.chaptered()
        let sut = loadedPresentation(book)
        sut.open(book, animated: true)
        XCTAssertEqual(sut.progress, 1, "the target")
        sut.renderedProgress = 0.6

        let start = try XCTUnwrap(sut.beginInteractive())
        try await Task.sleep(for: .milliseconds(800))

        XCTAssertEqual(start.progress, 0.6, accuracy: 0.0001)
        XCTAssertEqual(sut.progress, 0.6, accuracy: 0.0001)
        XCTAssertFalse(sut.isFullyOpen, "the interrupted open must not settle by itself")
    }

    func test_settle_usesTheSpecSpring() {
        XCTAssertEqual(PlayerPresentation.animation, .spring(response: 0.35, dampingFraction: 0.86))
    }
}
