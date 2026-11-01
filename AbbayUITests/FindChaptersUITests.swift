//
//  FindChaptersUITests.swift
//  AbbayUITests
//

import XCTest

/// Experimental *Find chapters*: an imported book with no chapters (*Seeded Plain Book*) gets a
/// pill in the Chapters pill's place; it searches the audio and the chapters it finds replace it
/// with the Chapters pill, whose list offers to remove them again.
///
/// `-stubChapterHeadings` turns the switch on and makes the stub engine read out "Chapter One." at
/// 10 s, "Chapter Two." at 70 s and "Chapter Three." at 130 s, in 10 s steps a quarter of a second
/// apart. Without it (`-stubReadAlongEngine`) the text has no headings. Needs iOS 26's engine.
final class FindChaptersUITests: XCTestCase {
    var app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard #available(iOS 26, *) else {
            throw XCTSkip("Find chapters needs iOS 26")
        }
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var findPill: XCUIElement { element(AccessibilityID.Player.findChapters) }
    private var chaptersPill: XCUIElement { element(AccessibilityID.Player.chapters) }

    private func launch(_ extra: [String]) {
        app.launchArguments = [LaunchArgument.seedLibrary, LaunchArgument.resetSettings] + extra
        app.launch()
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 20), "no library")
    }

    /// Opens *Seeded Plain Book*, the seed with no chapters, without playing it.
    private func openPlainBook(file: StaticString = #filePath, line: UInt = #line) throws {
        var title: XCUIElement?
        for index in 0..<6 {
            let candidate = element(AccessibilityID.Element.title(AccessibilityID.Library.row(index)))
            if candidate.exists, candidate.label == "Seeded Plain Book" {
                title = candidate
                break
            }
        }
        try XCTUnwrap(title, "no plain seed", file: file, line: line).tap()
        let close = element(AccessibilityID.Player.close)
        XCTAssertTrue(close.waitForExistence(timeout: 15), "the player did not open", file: file, line: line)
        XCTAssertTrue(element(AccessibilityID.Player.speed).waitForExistence(timeout: 5), file: file, line: line)
    }

    // MARK: - Tests

    func test_switchOff_noPill() throws {
        launch([LaunchArgument.stubReadAlongEngine])
        try openPlainBook()

        XCTAssertFalse(findPill.exists, "experimental: off by default")
        XCTAssertFalse(chaptersPill.exists)
    }

    func test_find_showsProgress_thenTheChapters_andRemoveTakesThemAway() throws {
        launch([LaunchArgument.stubChapterHeadings])
        try openPlainBook()
        XCTAssertTrue(findPill.waitForExistence(timeout: 5), "no Find chapters pill")
        XCTAssertFalse(chaptersPill.exists)

        findPill.tap()
        let deadline = Date().addingTimeInterval(5)
        while !findPill.label.hasPrefix("Finding chapters"), Date() < deadline { usleep(100_000) }
        XCTAssertTrue(findPill.label.hasPrefix("Finding chapters"), "no progress: \(findPill.label)")

        XCTAssertTrue(chaptersPill.waitForExistence(timeout: 20), "no chapters found")
        XCTAssertFalse(findPill.exists, "the Chapters pill takes its place")
        // Shown while the search goes on: the pill carries its percentage, the list a Stop.
        XCTAssertFalse((chaptersPill.value as? String ?? "").isEmpty, "no progress on the Chapters pill")
        chaptersPill.tap()
        XCTAssertTrue(element(AccessibilityID.Player.chaptersPanel).waitForExistence(timeout: 5))
        XCTAssertTrue(
            element(AccessibilityID.Player.stopFindingChapters).waitForExistence(timeout: 3),
            "no Stop while more are found"
        )
        XCTAssertTrue(element(AccessibilityID.Player.chapter(1)).exists, "the first chapters, before the end")
        for (index, title) in ["Chapter One", "Chapter Two", "Chapter Three"].enumerated() {
            let row = element(AccessibilityID.Player.chapter(index))
            XCTAssertTrue(row.waitForExistence(timeout: 5), "no row \(index)")
            XCTAssertTrue(row.label.contains(title), "row \(index) reads \(row.label)")
        }

        let remove = element(AccessibilityID.Player.removeFoundChapters)
        XCTAssertTrue(remove.waitForExistence(timeout: 15), "no Remove found chapters once done")
        XCTAssertFalse(element(AccessibilityID.Player.stopFindingChapters).exists)
        remove.tap()

        XCTAssertTrue(element(AccessibilityID.Player.chaptersPanel).waitForNonExistence(timeout: 5), "the panel stayed")
        XCTAssertTrue(findPill.waitForExistence(timeout: 5), "Find chapters is offered again")
        XCTAssertFalse(chaptersPill.exists)
    }

    func test_cancel_stopsTheSearch() throws {
        launch([LaunchArgument.stubChapterHeadings])
        try openPlainBook()
        XCTAssertTrue(findPill.waitForExistence(timeout: 5))

        findPill.tap()
        let deadline = Date().addingTimeInterval(5)
        while !findPill.label.hasPrefix("Finding chapters"), Date() < deadline { usleep(100_000) }
        findPill.tap()

        XCTAssertTrue(waitForLabel(of: findPill, "Find chapters"), "still searching: \(findPill.label)")
        sleep(12)
        XCTAssertFalse(chaptersPill.exists, "a search stopped before any heading found chapters")
    }

    /// Its own switch in Settings › Experimental, under Read-along's, off by default, explained in
    /// both languages.
    func test_settingsSwitch_offByDefault_explained() throws {
        let cases = [
            ("en", "en_US", "Find chapters", "Chapter One"),
            ("pt-BR", "pt_BR", "Buscar capítulos", "Capítulo um")
        ]
        for (language, locale, label, word) in cases {
            launch([LaunchArgument.stubReadAlongEngine, "-AppleLanguages", "(\(language))", "-AppleLocale", locale])
            element(AccessibilityID.Library.toolbarSettings).tap()
            let toggle = element(AccessibilityID.Settings.findChapters)
            for _ in 0..<8 where !(toggle.exists && toggle.isHittable) { app.swipeUp() }
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), "\(language): no Find chapters switch")
            XCTAssertEqual(toggle.label, label)
            XCTAssertEqual(toggle.value as? String, "0", "\(language): experimental, off by default")
            let footer = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", word)).firstMatch
            XCTAssertTrue(footer.waitForExistence(timeout: 5), "\(language): no footer mentioning \"\(word)\"")
            app.terminate()
        }
    }

    /// Stop from the list once chapters are showing: they stay, the search ends, and the list
    /// offers to remove them.
    func test_stopFromTheList_keepsTheChaptersFound() throws {
        launch([LaunchArgument.stubChapterHeadings])
        try openPlainBook()
        XCTAssertTrue(findPill.waitForExistence(timeout: 5))
        findPill.tap()
        XCTAssertTrue(chaptersPill.waitForExistence(timeout: 20), "no chapters found")
        chaptersPill.tap()
        let stop = element(AccessibilityID.Player.stopFindingChapters)
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "no Stop")

        stop.tap()

        XCTAssertTrue(
            element(AccessibilityID.Player.removeFoundChapters).waitForExistence(timeout: 5),
            "the search didn't end"
        )
        XCTAssertTrue(element(AccessibilityID.Player.chapter(0)).exists, "the chapters found went")
    }

    private func waitForLabel(of element: XCUIElement, _ label: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.label != label, Date() < deadline { usleep(100_000) }
        return element.label == label
    }
}
