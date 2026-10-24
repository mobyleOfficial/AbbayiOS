//
//  NoticeCenterTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The one surfacing mechanism (#115): one notice at a time, announced once, gone on its own.
final class NoticeCenterTests: XCTestCase {
    private var announced: [String] = []

    private func makeCenter(duration: TimeInterval = 60) -> NoticeCenter {
        NoticeCenter(displayDuration: { duration }, announce: { [weak self] in self?.announced.append($0) })
    }

    // MARK: - Showing

    func test_report_onMain_showsTheNoticeAtOnceAndAnnouncesIt() {
        let center = makeCenter()

        center.report(.saveFailed)

        XCTAssertEqual(center.current?.notice, .saveFailed)
        XCTAssertEqual(center.current?.message, Localizable.noticeSaveFailed.localized)
        XCTAssertEqual(announced, [Localizable.noticeSaveFailed.localized])
    }

    func test_reportingTheShownNoticeAgain_keepsItAndDoesNotAnnounceTwice() {
        let center = makeCenter()
        center.report(.chapterFailed)
        let first = center.current?.id

        center.report(.chapterFailed)

        XCTAssertEqual(center.current?.id, first)
        XCTAssertEqual(announced.count, 1)
    }

    func test_aNewNotice_replacesTheShownOne() {
        let center = makeCenter()
        center.report(.chapterFailed)

        center.report(.streamingOffline)

        XCTAssertEqual(center.current?.notice, .streamingOffline)
        XCTAssertEqual(announced.count, 2)
    }

    /// The player and Core Data report from background queues.
    func test_report_fromABackgroundThread_showsOnMain() {
        let center = makeCenter()
        let shown = expectation(description: "shown on main")

        DispatchQueue.global().async {
            center.report(.audioUnavailable)
            DispatchQueue.main.async {
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(center.current?.notice, .audioUnavailable)
                shown.fulfill()
            }
        }

        wait(for: [shown], timeout: 2)
    }

    // MARK: - Dismissing

    func test_theNotice_dismissesItselfAfterTheDisplayDuration() {
        let center = makeCenter(duration: 0.05)
        center.report(.saveFailed)
        XCTAssertNotNil(center.current)

        let gone = expectation(description: "dismissed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertNil(center.current)
            gone.fulfill()
        }
        wait(for: [gone], timeout: 2)
    }

    func test_dismiss_hidesTheNoticeNow() {
        let center = makeCenter()
        center.report(.saveFailed)

        center.dismiss()

        XCTAssertNil(center.current)
    }

    // MARK: - Messages

    func test_importMessage_namesASingleFile() {
        let message = Notice.importFailed(fileNames: ["Broken.mp3"]).message

        XCTAssertEqual(message, "Couldn't import “Broken.mp3”.")
    }

    func test_importMessage_countsAndListsSeveralFiles() {
        let message = Notice.importFailed(fileNames: ["A.mp3", "B.mp3"]).message

        XCTAssertTrue(message.hasPrefix("Couldn't import 2 files: "), message)
        XCTAssertTrue(message.contains("A.mp3"), message)
        XCTAssertTrue(message.contains("B.mp3"), message)
    }

    /// A big multi-select stays readable in a banner: three names, then "N more".
    func test_importMessage_listsAtMostThreeNamesThenHowManyMore() {
        let names = (1...5).map { "File \($0).mp3" }

        let message = Notice.importFailed(fileNames: names).message

        XCTAssertTrue(message.hasPrefix("Couldn't import 5 files: "), message)
        XCTAssertTrue(message.contains("File 3.mp3"), message)
        XCTAssertFalse(message.contains("File 4.mp3"), message)
        XCTAssertTrue(message.contains("2 more"), message)
    }

    func test_fileMissingMessage_namesTheBookAndSaysHowToRecover() {
        let message = Notice.fileMissing(title: "Dracula").message

        XCTAssertTrue(message.contains("Dracula"), message)
        XCTAssertTrue(message.contains("Import it again"), message)
    }

    func test_title_fallsBackToTheFileNameWhenTheBookHasNoTitle() {
        let untitled = AudioModel(url: URL(fileURLWithPath: "/books/My Book.m4b"))
        let titled = AudioModel(title: "Title", url: URL(fileURLWithPath: "/books/My Book.m4b"))

        XCTAssertEqual(Notice.title(of: untitled), "My Book")
        XCTAssertEqual(Notice.title(of: titled), "Title")
    }
}
