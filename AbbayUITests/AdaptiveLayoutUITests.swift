//
//  AdaptiveLayoutUITests.swift
//  AbbayUITests
//

import XCTest

/// The adaptive layout (#255): browsing, the player beside it, and the chapters beside the player
/// when the window has room for two panes; the full-screen player and the chapter panel when it
/// doesn't. The same tests run on every simulator and assert what that window's width calls for,
/// so they hold on an iPhone, both Duo displays and an iPad.
final class AdaptiveLayoutUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func launch(_ extra: [String] = []) {
        app.launchArguments = [
            LaunchArgument.seedLibrary,
            LaunchArgument.seedPlayableBook,
            LaunchArgument.seedArtwork,
            LaunchArgument.seedLastPlayed,
            LaunchArgument.seedFillerBooks,
            LaunchArgument.stubLibriVox,
            LaunchArgument.resetSettings
        ] + extra
        app.launch()
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 20), "no library")
    }

    private func cell(titled title: String, maxRows: Int = 16) -> XCUIElement? {
        for index in 0..<maxRows {
            let candidate = element(AccessibilityID.Element.title(AccessibilityID.Library.row(index)))
            if candidate.exists, candidate.label == title { return candidate }
        }
        return nil
    }

    /// Opens a book's player from its cell, and waits for the player's title.
    private func openPlayer(titled title: String) throws {
        let target = try XCTUnwrap(cell(titled: title), "no cell titled \(title)")
        target.tap()
        XCTAssertTrue(element(AccessibilityID.Player.title).waitForExistence(timeout: 10), "the player did not open")
        sleep(1)
    }

    /// Whether the window is split: the player then sits beside the library, not over it.
    private var playerIsBesideLibrary: Bool {
        let list = element(AccessibilityID.Library.list)
        let title = element(AccessibilityID.Player.title)
        guard list.exists, title.exists else { return false }
        return title.frame.minX >= list.frame.maxX - 1
    }

    /// Asks for a screenshot named `<ABBAY_SHOTS_PREFIX>-<name>.png` in `ABBAY_SHOTS_DIR` (pass them
    /// as `TEST_RUNNER_ABBAY_SHOTS_DIR` / `TEST_RUNNER_ABBAY_SHOTS_PREFIX` to xcodebuild). The test
    /// can't capture the unfolded iPhone Duo's inner display itself (`XCUIScreen.main` and
    /// `app.screenshot()` both return the dark outer one), so it writes `<name>.request` and waits
    /// while a script on the Mac takes the shot with `simctl io screenshot` and deletes the
    /// request. Does nothing without the directory.
    private func shot(_ name: String, waits: Bool = true) {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["ABBAY_SHOTS_DIR"], !directory.isEmpty else { return }
        let prefix = env["ABBAY_SHOTS_PREFIX"].map { "\($0)-" } ?? ""
        let request = URL(fileURLWithPath: directory).appendingPathComponent("\(prefix)\(name).request")
        try? Data().write(to: request)
        guard waits else { return }
        let deadline = Date().addingTimeInterval(20)
        while FileManager.default.fileExists(atPath: request.path), Date() < deadline {
            usleep(200_000)
        }
    }

    // MARK: - Tests

    /// Library, player and chapters: on a wide window the library stays beside the player, and the
    /// chapters take the library's place; on a narrow one the player covers the library and the
    /// chapters float over the player. Closing the player brings browsing back either way.
    func test_playerAndChapters_followTheWindowsRoom() throws {
        launch()
        shot("1-library")

        try openPlayer(titled: "Seeded Chaptered Book")
        let wide = playerIsBesideLibrary
        shot("2-player")

        let chapters = element(AccessibilityID.Player.chapters)
        XCTAssertTrue(chapters.waitForExistence(timeout: 5), "no Chapters pill")
        chapters.tap()
        let row = element(AccessibilityID.Player.chapter(0))
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the chapters did not open")
        sleep(1)
        shot("3-chapters")
        if wide {
            XCTAssertTrue(element(AccessibilityID.Player.title).isHittable, "the chapters hid the player")
            // #271: the player on the left, the chapters on its right.
            XCTAssertGreaterThan(
                row.frame.minX,
                element(AccessibilityID.Player.title).frame.maxX,
                "the chapters are not on the player's right"
            )
            let add = element(AccessibilityID.Library.toolbarAdd)
            XCTAssertFalse(add.exists && add.isHittable, "the covered library's toolbar is still showing")
            // A chapter tap keeps the chapters open beside the player.
            row.tap()
            sleep(1)
            XCTAssertTrue(element(AccessibilityID.Player.chapter(0)).exists, "a chapter tap closed the pane")
            chapters.tap()
            XCTAssertTrue(
                element(AccessibilityID.Library.list).waitForExistence(timeout: 5),
                "closing the chapters did not bring the library back"
            )
            XCTAssertTrue(element(AccessibilityID.Player.title).exists, "closing the chapters closed the player")
        } else {
            element(AccessibilityID.Player.chapters).tap()
            XCTAssertTrue(element(AccessibilityID.Player.chaptersPanel).waitForNonExistence(timeout: 5))
        }

        element(AccessibilityID.Player.close).tap()
        XCTAssertTrue(element(AccessibilityID.Player.title).waitForNonExistence(timeout: 5), "the player did not close")
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 5), "browsing did not come back")
        // A book was loaded by the chapter tap (wide) or not at all (narrow): either way, closing
        // the player leaves browsing, with the mini player only for a loaded book.
        sleep(1)
        shot("4-closed")
    }

    /// Landscape, newly supported (the unfolded Duo's inner display is landscape): the library and
    /// the player still lay out and close, whatever the window's split.
    func test_landscape_libraryAndPlayerStillWork() throws {
        launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        sleep(2)
        shot("5-landscape-library")
        try openPlayer(titled: "Seeded Chaptered Book")
        let play = element(AccessibilityID.Player.transport(AccessibilityID.Transport.play))
        XCTAssertTrue(play.isHittable, "no play button")
        shot("6-landscape-player")
        element(AccessibilityID.Player.close).tap()
        XCTAssertTrue(element(AccessibilityID.Player.title).waitForNonExistence(timeout: 5), "the player did not close")
    }

    /// Evidence only (it runs when `ABBAY_SHOTS_DIR` is set): the import picker as it opens. On a
    /// regular width the old sheet-wrapped picker was first laid out against the left edge (#255).
    func test_importPicker_opening() throws {
        guard ProcessInfo.processInfo.environment["ABBAY_SHOTS_DIR"] != nil else {
            throw XCTSkip("screenshots only")
        }
        launch()
        element(AccessibilityID.Library.toolbarAdd).tap()
        let item = element(AccessibilityID.Library.menuImport)
        XCTAssertTrue(item.waitForExistence(timeout: 5), "no Import file item")
        // A burst of screenshots from the Mac, asked for just before the tap, catches the opening.
        shot("7-import-burst", waits: false)
        item.tap()
        sleep(4)
        shot("8-import-open")
    }

    /// #267: on a split window, opening the player beside the grid changes its column count; the
    /// book that was at the top of the scrolled grid stays in view. Skipped in one pane.
    func test_scrolledGrid_keepsItsTopBook_whenThePlayerOpensBeside() throws {
        launch([LaunchArgument.seedLongBook])
        let list = element(AccessibilityID.Library.list)
        for _ in 0..<3 { list.swipeUp(velocity: .slow) }
        sleep(1)
        let cellTitle = NSPredicate(format: "identifier BEGINSWITH 'library.row.' AND identifier ENDSWITH '.title'")
        let titles = app.descendants(matching: .any).matching(cellTitle).allElementsBoundByIndex
        let visible = titles.filter { $0.frame.minY > list.frame.minY + 60 && $0.frame.maxY < list.frame.maxY }
        let top = try XCTUnwrap(visible.min { $0.frame.minY < $1.frame.minY }, "no visible cell")
        let topTitle = top.label
        let openTarget = try XCTUnwrap(visible.last, "no cell to open")
        openTarget.tap()
        XCTAssertTrue(element(AccessibilityID.Player.title).waitForExistence(timeout: 10))
        guard playerIsBesideLibrary else { throw XCTSkip("one pane: the player covers the grid") }
        sleep(1)
        shot("9-scroll-anchor")
        let kept = app.descendants(matching: .any).matching(cellTitle)
            .matching(NSPredicate(format: "label == %@", topTitle))
            .firstMatch
        XCTAssertTrue(kept.exists, "the top book is gone")
        XCTAssertTrue(
            kept.frame.maxY > list.frame.minY && kept.frame.minY < list.frame.maxY,
            "\(topTitle) left the visible grid"
        )
    }

    /// #265: the sheets and alerts a user meets, on whatever window this runs (an iPad shows them as
    /// form sheets): Settings, the player's speed sheet and LibriVox's large-download alert. Each
    /// opens with its controls inside the window, and closes.
    func test_sheets_openInsideTheWindow() throws {
        launch()
        let window = app.windows.firstMatch.frame

        element(AccessibilityID.Library.toolbarSettings).tap()
        let done = element(AccessibilityID.Settings.done)
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Settings did not open")
        XCTAssertTrue(window.contains(done.frame), "Settings' Done is outside the window")
        sleep(1)
        shot("10-settings")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Settings did not close")

        try openPlayer(titled: "Seeded Chaptered Book")
        element(AccessibilityID.Player.speed).tap()
        let value = element(AccessibilityID.Speed.value)
        XCTAssertTrue(value.waitForExistence(timeout: 10), "the speed sheet did not open")
        XCTAssertTrue(window.contains(value.frame), "the speed value is outside the window")
        sleep(1)
        shot("11-speed")
        // Closed the way a user does it on any window: a drag down from the sheet's top edge,
        // above its title (a swipe on the sheet's middle lands on the slider; a tap outside
        // doesn't close the unfolded Duo's bottom sheet).
        // Relative to an element: on the unfolded iPhone Duo, `app.coordinate` points don't land
        // where they do on other screens, while an element's own coordinates do.
        let top = value.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -50))
        top.press(forDuration: 0.1, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 500)))
        sleep(1)
        shot("11b-speed-after-drag")
        XCTAssertTrue(value.waitForNonExistence(timeout: 5), "the speed sheet did not close")
        element(AccessibilityID.Player.close).tap()

        app.terminate()
        app.launchArguments = [
            LaunchArgument.stubLibriVox,
            LaunchArgument.resetLibrary,
            LaunchArgument.resetSettings,
            LaunchArgument.stubDownloadStates,
            LaunchArgument.stubPathCellular
        ]
        app.launch()
        element(AccessibilityID.Root.tabSearch).tap()
        let card = element(AccessibilityID.Search.card(0))
        XCTAssertTrue(card.waitForExistence(timeout: 15), "no Popular card")
        card.tap()
        let download = element(AccessibilityID.Detail.download)
        XCTAssertTrue(download.waitForExistence(timeout: 15), "no Download")
        download.tap()
        let wait = element(AccessibilityID.Detail.cellularWait)
        XCTAssertTrue(wait.waitForExistence(timeout: 10), "no large-download alert")
        XCTAssertTrue(window.contains(wait.frame), "the alert is outside the window")
        sleep(1)
        shot("12-download-alert")
        wait.tap()
    }

    /// Every library cell fits the window: none runs past the trailing edge or under the system's
    /// side strip (#251), at any width.
    func test_libraryGrid_fitsTheWindow() throws {
        launch()
        let list = element(AccessibilityID.Library.list)
        let frame = list.frame
        for index in 0..<6 {
            let title = element(AccessibilityID.Element.title(AccessibilityID.Library.row(index)))
            guard title.exists else { continue }
            XCTAssertLessThanOrEqual(title.frame.maxX, frame.maxX + 0.5, "cell \(index) runs past the library")
        }
    }
}
