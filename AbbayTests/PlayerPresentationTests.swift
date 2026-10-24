//
//  PlayerPresentationTests.swift
//  AbbayTests
//

@testable import Abbay
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
}
