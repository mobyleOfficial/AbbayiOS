//
//  AudioDomainUITests.swift
//  AbbayUITests
//

import XCTest
#if canImport(AppIntentsTesting) && canImport(MediaIntents)
import AppIntents
import AppIntentsTesting
import MediaIntents
#endif

/// iOS 27's App Intents audio domain, end to end (#129): `AppIntentsTesting` runs the app's value
/// query and `PlayAudioDomainIntent` through the real App Intents stack in the running app, the
/// same path Siri takes after it has understood a request. Only the speech recognition is skipped.
/// Below iOS 27 the domain doesn't exist and these skip.
final class AudioDomainUITests: XCTestCase {
    var app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    #if canImport(AppIntentsTesting) && canImport(MediaIntents)
    @MainActor
    func test_audioSearch_findsASeededBook_andPlayAudioPlaysIt() async throws {
        guard #available(iOS 27, *) else { throw XCTSkip("the audio domain is iOS 27+") }
        app.launchArguments = [LaunchArgument.seedLibrary]
        app.launch()
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 20))
        XCTAssertFalse(element(AccessibilityID.MiniPlayer.bar).exists, "nothing should be loaded yet")

        let definitions = IntentDefinitions(bundleIdentifier: "com.edyuto.Abbay")
        let result = try await definitions.valueQueries["AudioDomainBookQuery"]
            .values(for: AudioSearch(criteria: .searchQuery("Seeded Chaptered")))
        XCTAssertEqual(result.items.count, 1)
        let book = try result.items[0].as(definitions.entities["AudioDomainBookEntity"])
        let title: String = try book.title
        XCTAssertEqual(title, "Seeded Chaptered Book")

        try await definitions.intents["PlayAudioDomainIntent"].makeIntent(audioEntity: book).run()

        let bar = element(AccessibilityID.MiniPlayer.bar)
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "the intent didn't load the book")
        XCTAssertTrue(bar.label.contains("Seeded Chaptered Book"), "unexpected bar \"\(bar.label)\"")
    }

    @MainActor
    func test_audioSearch_withNoTitle_offersTheLibrary() async throws {
        guard #available(iOS 27, *) else { throw XCTSkip("the audio domain is iOS 27+") }
        app.launchArguments = [LaunchArgument.seedLibrary]
        app.launch()
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 20))

        let definitions = IntentDefinitions(bundleIdentifier: "com.edyuto.Abbay")
        let result = try await definitions.valueQueries["AudioDomainBookQuery"]
            .values(for: AudioSearch(criteria: .unspecified))
        XCTAssertGreaterThanOrEqual(result.items.count, 2, "the seeded library has at least two books")
    }
    #endif
}
