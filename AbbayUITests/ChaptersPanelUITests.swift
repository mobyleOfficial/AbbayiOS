//
//  ChaptersPanelUITests.swift
//  AbbayUITests
//

import XCTest

/// The player's chapter panel (#166 G2), which replaced the chapter list on the player and its
/// drag-to-collapse from the list's top: it opens at the current chapter, scrolls on its own, and
/// closes from its top, a tap outside or its pill, while the header still collapses the player.
extension MiniPlayerUITests {
    // MARK: - The chapter panel (#166 G2)

    /// Opens the chapter panel from its pill and waits for its handle.
    func openChaptersPanel(file: StaticString = #filePath, line: UInt = #line) {
        let pill = element(AccessibilityID.Player.chapters)
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "no Chapters pill", file: file, line: line)
        pill.tap()
        XCTAssertTrue(
            element(AccessibilityID.Player.chaptersPanel).waitForExistence(timeout: 5),
            "the chapter panel did not open",
            file: file,
            line: line
        )
    }

    /// The chapter row at the top of the panel's visible area: the loaded rows only, in one query.
    /// Asking each of 60 rows `isHittable` takes about a second per row on iOS 17.
    private func topVisibleChapter(below top: CGFloat, above bottom: CGFloat) -> Int? {
        let prefix = AccessibilityID.Player.chapter(0).dropLast()
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", String(prefix)))
            .allElementsBoundByIndex
        let visible = rows.compactMap { row -> (index: Int, minY: CGFloat)? in
            let frame = row.frame
            guard frame.midY >= top, frame.midY <= bottom,
                  let index = Int(row.identifier.dropFirst(prefix.count)) else { return nil }
            return (index, frame.minY)
        }
        return visible.min { $0.minY < $1.minY }?.index
    }

    /// The panel opens over the player with the current chapter in view: a chapter tap far down
    /// the long book's list loads it there, and the reopened panel starts at that chapter, not
    /// at the top. Chapter 11 starts at 10:00, inside the seed's audio (#147).
    func test_chaptersPanel_opensAtTheCurrentChapter() throws {
        launch([LaunchArgument.seedLibrary, LaunchArgument.seedLongBook])
        assertResolves(AccessibilityID.Library.list)
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Long Book"), "no seeded long book")
        element(AccessibilityID.Element.title(AccessibilityID.Library.row(index))).tap()
        waitForPlayerToArrive()
        openChaptersPanel()
        let first = element(AccessibilityID.Player.chapter(0))
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isHittable, "nothing played yet: the panel opens at the first chapter")

        // Scroll the panel's list until chapter 11 shows, then tap it.
        let target = element(AccessibilityID.Player.chapter(10))
        for _ in 0..<6 where !(target.exists && target.isHittable) {
            if first.exists { first.swipeUp(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(target.isHittable, "chapter 11 never came into view")
        target.tap()
        XCTAssertTrue(
            element(AccessibilityID.Player.chaptersPanel).waitForNonExistence(timeout: 5),
            "a chapter tap closes the panel"
        )

        openChaptersPanel()
        let current = element(AccessibilityID.Player.chapter(10))
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertTrue(current.isHittable, "the reopened panel does not show the current chapter")
        XCTAssertTrue(current.isSelected, "chapter 11 is not marked current")
        XCTAssertFalse(element(AccessibilityID.Player.chapter(0)).isHittable, "the panel opened at the top")
        pausePlayback()
    }

    /// A drag down from the panel's top closes only the panel: the player stays open. The header
    /// drag still collapses the player afterwards.
    func test_dragAtThePanelsTop_closesOnlyThePanel() throws {
        try loadSeededBook(titled: "Seeded Chaptered Book")
        let bar = element(AccessibilityID.MiniPlayer.bar)
        let before = restingFrame(of: bar)
        bar.tap()
        waitForPlayerToArrive()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "not settled open")
        openChaptersPanel()
        let handle = element(AccessibilityID.Player.chaptersPanel)
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 160)))

        XCTAssertTrue(handle.waitForNonExistence(timeout: 5), "the drag did not close the panel")
        XCTAssertTrue(transportPlay.exists, "the drag closed the player too")
        XCTAssertFalse(bar.exists, "the player must stay open")

        let header = grabberCenter()
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        header.press(forDuration: 0.1, thenDragTo: bottom)
        assertCollapsedIntoBar(restingAt: before)
    }

    /// Tapping outside the panel, or the pill (now ✕), closes it; the player stays open.
    func test_tapOutsideOrOnThePill_closesThePanel() throws {
        try loadSeededBook(titled: "Seeded Chaptered Book")
        element(AccessibilityID.MiniPlayer.bar).tap()
        waitForPlayerToArrive()
        let panel = element(AccessibilityID.Player.chaptersPanel)

        openChaptersPanel()
        element(AccessibilityID.Player.chapters).tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "the ✕ pill did not close the panel")

        openChaptersPanel()
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 12, dy: element(AccessibilityID.Player.close).frame.maxY + 40))
            .tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "a tap outside did not close the panel")
        XCTAssertTrue(transportPlay.exists, "the player closed")
    }

    /// The final review's long-list check (60 chapters), now inside the panel: its list scrolls
    /// down and back up, and no drag on it moves or collapses the player.
    func test_longChapterList_scrollsInThePanel_andNeverCollapses() throws {
        launch([LaunchArgument.seedLibrary, LaunchArgument.seedLongBook])
        assertResolves(AccessibilityID.Library.list)
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Long Book"), "no seeded long book")
        element(AccessibilityID.Element.title(AccessibilityID.Library.row(index))).tap()
        waitForPlayerToArrive()
        openChaptersPanel()
        let first = element(AccessibilityID.Player.chapter(0))
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let top = first.frame.minY
        let bottom = element(AccessibilityID.Player.chapters).frame.minY
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let upper = origin.withOffset(CGVector(dx: app.frame.midX, dy: top + 40))
        let lower = origin.withOffset(CGVector(dx: app.frame.midX, dy: bottom - 40))

        for _ in 0..<3 {
            lower.press(forDuration: 0.05, thenDragTo: upper, withVelocity: 1500, thenHoldForDuration: 0)
        }
        sleep(2)
        let middle = try XCTUnwrap(topVisibleChapter(below: top, above: bottom), "no chapter row in the panel")
        XCTAssertGreaterThanOrEqual(middle, 8, "the list did not scroll (top visible row \(middle))")
        XCTAssertTrue(transportPlay.isHittable, "scrolling the panel moved the player")

        // A fast drag down mid-list scrolls back up; the panel and the player stay.
        upper.press(forDuration: 0.05, thenDragTo: lower, withVelocity: 2500, thenHoldForDuration: 0)
        sleep(2)
        let afterDown = try XCTUnwrap(topVisibleChapter(below: top, above: bottom), "no chapter row in the panel")
        XCTAssertLessThan(afterDown, middle, "the drag down mid-list did not scroll the list")
        XCTAssertTrue(element(AccessibilityID.Player.chaptersPanel).exists, "a drag mid-list closed the panel")
        XCTAssertTrue(transportPlay.isHittable, "a drag mid-list moved the player")
    }

    /// Pauses whatever plays, from the details screen.
    private func pausePlayback() {
        if transportPlay.exists, transportPlay.label == "Pause" { transportPlay.tap() }
    }
}
