//
//  StoreScreenshotsUITests.swift
//  AbbayUITests
//

import XCTest

/// Drives the five App Store screens (#252) on a simulator that holds a demo library, and asks
/// `StoreConfig/screenshots/capture.sh` to take each shot (`xcrun simctl io screenshot`, which also
/// sees the unfolded iPhone Duo's inner display). Runs only from that script: without
/// `ABBAY_STORE_SHOTS_DIR` every test here skips.
///
/// The screens, per language's library:
/// 1. the library, with the hero book loaded in the mini player;
/// 2. its player (beside the library on a split window);
/// 3. its chapters (the panel, or beside the player);
/// 4. LibriVox search (Popular in English, a "Machado de Assis" search in Portuguese);
/// 5. a LibriVox book page (*Dracula*, *O Alienista*).
///
/// Nothing is downloaded or deleted, so a rerun starts from the same state.
final class StoreScreenshotsUITests: XCTestCase {
    private var app = XCUIApplication()

    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var directory: String? { environment["ABBAY_STORE_SHOTS_DIR"].flatMap { $0.isEmpty ? nil : $0 } }
    private var prefix: String { environment["ABBAY_STORE_SHOTS_PREFIX"] ?? "shot" }
    private var isPortuguese: Bool { environment["ABBAY_STORE_SHOTS_LANG"] == "pt-BR" }

    /// The book playing in the shots, the search and the book page, per library.
    private var heroTitle: String { isPortuguese ? "Dom Casmurro" : "Pride and Prejudice" }
    private var searchedTitle: String { isPortuguese ? "Alienista" : "Dracula" }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        guard directory != nil else {
            throw XCTSkip("App Store screenshots run from StoreConfig/screenshots/capture.sh")
        }
        app = XCUIApplication()
    }

    // MARK: - Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The element, waited for. When it never comes, a `debug` shot shows the screen instead.
    private func need(_ identifier: String, timeout: TimeInterval = 30) -> XCUIElement {
        let found = element(identifier)
        if !found.waitForExistence(timeout: timeout) {
            shot("debug-\(identifier)")
            XCTFail("no \(identifier)")
        }
        return found
    }

    /// Writes `<prefix>-<name>.request` and waits while the script takes the shot and deletes it.
    private func shot(_ name: String) {
        guard let directory else { return }
        let request = URL(fileURLWithPath: directory).appendingPathComponent("\(prefix)-\(name).request")
        try? Data().write(to: request)
        let deadline = Date().addingTimeInterval(30)
        while FileManager.default.fileExists(atPath: request.path), Date() < deadline {
            usleep(200_000)
        }
    }

    private func launch() {
        let language = isPortuguese ? "pt-BR" : "en"
        let locale = isPortuguese ? "pt_BR" : "en_US"
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        dismissSiriPrompt()
        XCTAssertTrue(need(AccessibilityID.Library.list, timeout: 40).exists)
    }

    /// The first launch on a fresh simulator asks to use Abbay with Siri (the app requests it at
    /// launch); the alert would sit over the first shots.
    private func dismissSiriPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons.element(boundBy: 1)
        if springboard.alerts.firstMatch.waitForExistence(timeout: 5), allow.exists {
            allow.tap()
        }
    }

    // MARK: - Screens

    func test_storeScreens() throws {
        launch()
        // 1. The library, with the hero book loaded (Continue's Resume plays it).
        startHeroBook()
        let bar = need(AccessibilityID.MiniPlayer.bar, timeout: 40)
        XCTAssertTrue(bar.label.contains(heroTitle), "the bar plays \(bar.label), not \(heroTitle)")
        sleep(4)
        shot("1-library")

        // 2. Its player.
        bar.tap()
        _ = need(AccessibilityID.Player.title)
        sleep(4)
        shot("2-player")

        // 3. Its chapters, scrolled to the current one.
        need(AccessibilityID.Player.chapters).tap()
        _ = need(AccessibilityID.Player.chapter(0))
        sleep(5)
        shot("3-chapters")
        need(AccessibilityID.Player.chapters).tap()
        sleep(1)
        need(AccessibilityID.Player.close).tap()
        sleep(2)

        // 4. LibriVox search, and 5. a book page.
        let result = searchResult()
        shot("4-search")

        revealAboveMiniPlayer(result)
        result.tap()
        // Download, or Play when the book is already in the library.
        _ = need(AccessibilityID.Detail.view, timeout: 30)
        let action = element(AccessibilityID.Detail.download)
        if !action.waitForExistence(timeout: 20) {
            XCTAssertTrue(element(AccessibilityID.Detail.play).waitForExistence(timeout: 10), "no Download or Play")
        }
        // Wait for LibriVox's chapter titles (#258), then for the cover.
        let loading = element(AccessibilityID.Detail.chapterTitleLoading(0))
        let deadline = Date().addingTimeInterval(30)
        while loading.exists, Date() < deadline {
            usleep(250_000)
        }
        sleep(3)
        shot("5-detail")
    }

    /// Plays the hero book: Continue's Resume when the library remembers it as last played, else
    /// its cell's player (Play, then close), which also makes it last played for the Continue card.
    /// A copied library's last played can be hidden behind the simulator's cached preferences.
    private func startHeroBook() {
        let resume = element(AccessibilityID.Library.continueResume)
        if resume.waitForExistence(timeout: 15) {
            resume.tap()
            return
        }
        let isHero = NSPredicate(
            format: "identifier BEGINSWITH 'library.row.' AND identifier ENDSWITH '.title' AND label CONTAINS %@",
            heroTitle
        )
        let cell = app.descendants(matching: .any).matching(isHero).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 20), "no \(heroTitle) in the library")
        cell.tap()
        need(AccessibilityID.Player.transport(AccessibilityID.Transport.play)).tap()
        sleep(2)
        need(AccessibilityID.Player.close).tap()
        sleep(2)
    }

    /// Scrolls the search page until `target` sits above the mini player (a tap behind the bar
    /// opens the player instead).
    private func revealAboveMiniPlayer(_ target: XCUIElement) {
        let bar = element(AccessibilityID.MiniPlayer.bar)
        for _ in 0..<3 where bar.exists && target.frame.maxY > bar.frame.minY - 8 {
            let start = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -220)))
            sleep(1)
        }
    }

    /// Opens Search and returns the book to open: a Popular card in English, a "Machado de Assis"
    /// result in Portuguese.
    private func searchResult() -> XCUIElement {
        need(AccessibilityID.Root.tabSearch).tap()
        if isPortuguese {
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 30), "no search field")
            sleep(2)
            field.tap()
            field.typeText("Machado de Assis\n")
            let isResult = NSPredicate(
                format: "identifier BEGINSWITH 'search.result.' AND label CONTAINS[c] %@",
                searchedTitle
            )
            let result = app.buttons.matching(isResult).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 30), "no \(searchedTitle) result")
            // A short drag on the results hides the keyboard, which submitting leaves up on a
            // phone-sized window; the list is at its top, so it springs back.
            let keyboard = app.keyboards.firstMatch
            for _ in 0..<3 where keyboard.exists {
                let start = result.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 80)))
                _ = keyboard.waitForNonExistence(timeout: 2)
            }
            // Let the result covers arrive.
            sleep(6)
            return result
        }
        let isCard = NSPredicate(
            format: "identifier BEGINSWITH 'search.card.' AND label BEGINSWITH %@",
            searchedTitle
        )
        let result = app.buttons.matching(isCard).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 30), "no \(searchedTitle) card")
        sleep(6)
        return result
    }
}
