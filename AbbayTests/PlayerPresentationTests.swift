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
}
