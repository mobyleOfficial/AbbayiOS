// Throwaway screenshot driver for the G3/G7 PR. Not committed.
import XCTest

final class ZZShotDriverUITests: XCTestCase {
    var app = XCUIApplication()
    let env = ProcessInfo.processInfo.environment
    var dir: String { env["SHOT_DIR"] ?? "/Users/edyuto/Desktop/Projects/Mobyle/AbbayiOS/.superpowers/screens/g37" }
    var suffix: String { env["SHOT_SUFFIX"] ?? "after" }
    var prefix: String { env["SHOT_LANG"] == "pt-BR" ? "ptBR-" : "" }

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
    }

    func launch(_ args: [String]) {
        var all = args + [LaunchArgument.resetSettings]
        if env["SHOT_LANG"] == "pt-BR" {
            all += ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        } else {
            all += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        }
        app.launchArguments = all
        app.launch()
    }

    func el(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func shot(_ name: String, delay: UInt32 = 2) {
        sleep(delay)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let path = "\(dir)/\(prefix)\(name)-\(suffix).png"
        FileManager.default.createFile(atPath: path, contents: png)
    }

    func titleElement(_ title: String) -> XCUIElement? {
        for index in 0..<8 {
            let candidate = el(AccessibilityID.Element.title(AccessibilityID.Library.row(index)))
            if candidate.exists, candidate.label == title { return candidate }
        }
        return nil
    }

    var seeds: [String] {
        [LaunchArgument.seedLibrary, LaunchArgument.seedPlayableBook, LaunchArgument.seedArtwork,
         LaunchArgument.seedLastPlayed, LaunchArgument.seedTimeLeftEdges]
    }

    func openPlayer(_ title: String) {
        _ = el(AccessibilityID.Library.list).waitForExistence(timeout: 15)
        sleep(1)
        titleElement(title)?.tap()
        _ = el(AccessibilityID.Player.close).waitForExistence(timeout: 15)
        sleep(2)
    }

    func test_1_library() {
        launch(seeds)
        _ = el(AccessibilityID.Library.list).waitForExistence(timeout: 15)
        shot("library")
        app.swipeUp()
        shot("library-scrolled")
    }

    func test_2_miniPlayer() {
        launch(seeds)
        openPlayer(playableTitle)
        el(AccessibilityID.Player.transport(AccessibilityID.Transport.play)).tap()
        sleep(1)
        el(AccessibilityID.Player.close).tap()
        _ = el(AccessibilityID.MiniPlayer.bar).waitForExistence(timeout: 10)
        shot("library-miniplayer")
        // The speed sheet, from the player.
        el(AccessibilityID.MiniPlayer.bar).tap()
        _ = el(AccessibilityID.Player.speed).waitForExistence(timeout: 10)
        sleep(2)
        el(AccessibilityID.Player.speed).tap()
        _ = el(AccessibilityID.Speed.value).waitForExistence(timeout: 10)
        shot("speed-sheet")
    }

    func test_3_search() {
        launch(seeds)
        _ = el(AccessibilityID.Library.list).waitForExistence(timeout: 15)
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("Seeded P")
        shot("library-search")
        field.typeText("zzz")
        shot("library-search-noresults")
    }

    func test_4_empty() {
        launch([LaunchArgument.resetLibrary])
        _ = el(AccessibilityID.Library.empty).waitForExistence(timeout: 15)
        shot("library-empty")
    }

    func test_5_downloading() {
        launch([LaunchArgument.seedLibrary, LaunchArgument.seedArtwork, LaunchArgument.stubLibriVox,
                LaunchArgument.stubDownloadStates, LaunchArgument.stubPathCellular])
        el(AccessibilityID.Root.tabSearch).tap()
        _ = el(AccessibilityID.Search.card(0)).waitForExistence(timeout: 15)
        el(AccessibilityID.Search.card(0)).tap()
        _ = el(AccessibilityID.Detail.download).waitForExistence(timeout: 15)
        el(AccessibilityID.Detail.download).tap()
        if el(AccessibilityID.Detail.cellularWait).waitForExistence(timeout: 5) {
            el(AccessibilityID.Detail.cellularWait).tap()
        }
        sleep(1)
        el(AccessibilityID.Root.tabLibrary).tap()
        sleep(1)
        el(AccessibilityID.Root.tabLibrary).tap()
        shot("library-downloading")
    }

    func test_6_settings() {
        launch(seeds)
        _ = el(AccessibilityID.Library.toolbarSettings).waitForExistence(timeout: 15)
        el(AccessibilityID.Library.toolbarSettings).tap()
        _ = el(AccessibilityID.Settings.done).waitForExistence(timeout: 10)
        shot("settings")
        app.swipeUp()
        app.swipeUp()
        shot("settings-bottom")
    }

    func test_7_notice() {
        launch([LaunchArgument.seedLibrary, LaunchArgument.seedArtwork, LaunchArgument.stubFailingImport])
        _ = el(AccessibilityID.Library.toolbarAdd).waitForExistence(timeout: 15)
        sleep(1)
        el(AccessibilityID.Library.toolbarAdd).tap()
        _ = el(AccessibilityID.Library.menuImport).waitForExistence(timeout: 5)
        el(AccessibilityID.Library.menuImport).tap()
        _ = el(AccessibilityID.Notice.banner).waitForExistence(timeout: 10)
        shot("notice-banner", delay: 1)
    }

    func test_8_continueLoaded() {
        launch(seeds)
        openPlayer("Seeded Chaptered Book")
        el(AccessibilityID.Player.transport(AccessibilityID.Transport.play)).tap()
        sleep(1)
        el(AccessibilityID.Player.close).tap()
        _ = el(AccessibilityID.MiniPlayer.bar).waitForExistence(timeout: 10)
        shot("library-continue-playing")
    }

    func test_9_largestText() {
        app.launchArguments = seeds + [LaunchArgument.resetSettings, "-UIPreferredContentSizeCategoryName",
                                       "UICTContentSizeCategoryXXXL"]
            + (env["SHOT_LANG"] == "pt-BR" ? ["-AppleLanguages", "(pt-BR)"] : ["-AppleLanguages", "(en)"])
        app.launch()
        _ = el(AccessibilityID.Library.list).waitForExistence(timeout: 15)
        shot("library-xxxl")
        app.swipeUp()
        shot("library-xxxl-scrolled")
        openPlayer("Seeded Plain Book")
        el(AccessibilityID.Player.speed).tap()
        _ = el(AccessibilityID.Speed.value).waitForExistence(timeout: 10)
        shot("speed-sheet-xxxl")
    }

    private let playableTitle = "Seeded Playable Book"
}
