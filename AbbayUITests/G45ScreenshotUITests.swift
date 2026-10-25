import XCTest

/// Throwaway screenshot driver for the G4 + G5 PR. Not committed.
final class G45ScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!
    private var language = "en"

    override func setUp() {
        continueAfterFailure = true
    }

    private var dir: String { ProcessInfo.processInfo.environment["SHOT_DIR"] ?? NSTemporaryDirectory() }
    private var suffix: String { ProcessInfo.processInfo.environment["SHOT_SUFFIX"] ?? "after" }
    private var prefix: String { language == "en" ? "" : "ptBR-" }

    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 1.2)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let path = "\(dir)/\(prefix)\(name)-\(suffix).png"
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    private func wait(_ id: String, _ timeout: TimeInterval = 20) -> XCUIElement {
        let found = element(id)
        XCTAssertTrue(found.waitForExistence(timeout: timeout), "missing \(id)")
        return found
    }

    private func launch(_ extra: [String]) {
        app = XCUIApplication()
        let locale = language == "en" ? "en_US" : "pt_BR"
        app.launchArguments = ["-seedLibrary", "-stubLibriVox", "-AppleLanguages", "(\(language))", "-AppleLocale", locale] + extra
        app.launch()
        wait("root.tab.search").tap()
    }

    private func type(_ text: String) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText(text)
    }

    private func dismissKeyboard() {
        if app.keyboards.firstMatch.exists {
            app.keyboards.buttons.element(boundBy: app.keyboards.buttons.count - 1).tap()
        }
    }

    private func drive() {
        // Search
        launch([])
        wait("search.card.0")
        shot("search-popular")
        type("Stub")
        wait("search.result.0")
        dismissKeyboard()
        shot("search-results")
        app.searchFields.firstMatch.buttons.firstMatch.tap()
        type("zzzz")
        wait("search.noResults")
        dismissKeyboard()
        shot("search-noresults")
        app.terminate()

        launch(["-stubPathOffline"])
        type("Stub")
        wait("search.message")
        dismissKeyboard()
        shot("search-offline")
        app.terminate()

        // Book page, not downloaded, then downloaded (stub manager publishes nothing: complete)
        launch([])
        wait("search.card.0").tap()
        wait("detail.download")
        shot("detail")
        app.swipeUp()
        shot("detail-chapters")
        app.swipeDown()
        Thread.sleep(forTimeInterval: 0.6)
        element("detail.download").tap()
        wait("detail.play")
        shot("detail-downloaded")
        app.swipeUp()
        shot("detail-downloaded-chapters")
        app.navigationBars.buttons.firstMatch.tap()
        type("Stub")
        wait("search.result.0")
        dismissKeyboard()
        shot("search-results-inlibrary")
        app.terminate()

        // A long book (Emma, 24 chapters after this PR): scrolled, the action pins to the bar
        launch([])
        wait("search.card.5").tap()
        wait("detail.download")
        shot("detail-long")
        app.swipeUp()
        app.swipeUp()
        shot("detail-long-scrolled")
        app.terminate()

        // Downloading, held on cellular (Wait for Wi-Fi)
        launch(["-stubDownloadStates", "-stubPathCellular"])
        wait("search.card.0").tap()
        wait("detail.download").tap()
        wait("detail.cellular.wait").tap()
        wait("detail.cellularHold")
        shot("detail-downloading-hold")
        app.swipeUp()
        shot("detail-downloading-hold-chapters")
        app.terminate()
    }

    func test_en() {
        language = "en"
        drive()
    }

    func test_tint() {
        language = "en"
        launch(["-stubCovers"])
        wait("search.card.0").tap()
        wait("cover.loaded", 40)
        Thread.sleep(forTimeInterval: 1.5)
        shot("detail-cover-tint")
        app.terminate()
    }

    func test_ptBR() {
        language = "pt-BR"
        drive()
    }
}
