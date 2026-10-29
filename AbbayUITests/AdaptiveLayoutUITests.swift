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
    private func shot(_ name: String) {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["ABBAY_SHOTS_DIR"], !directory.isEmpty else { return }
        let prefix = env["ABBAY_SHOTS_PREFIX"].map { "\($0)-" } ?? ""
        let request = URL(fileURLWithPath: directory).appendingPathComponent("\(prefix)\(name).request")
        try? Data().write(to: request)
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
            XCTAssertLessThan(
                row.frame.maxX,
                element(AccessibilityID.Player.title).frame.minX,
                "the chapters are not beside the player"
            )
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
