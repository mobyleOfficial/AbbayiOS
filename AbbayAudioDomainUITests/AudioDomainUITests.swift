//
//  AudioDomainUITests.swift
//  AbbayAudioDomainUITests
//

import AppIntents
import AppIntentsTesting
import MediaIntents
import XCTest

/// iOS 27's App Intents audio domain, end to end (#129): `AppIntentsTesting` runs the app's value
/// query and `PlayAudioDomainIntent` through the real App Intents stack in the running app, the
/// same path Siri takes after it has understood a request. Only the speech recognition is skipped.
/// The bundle's deployment target is iOS 27 (`AppIntentsTesting` needs iOS 27 frameworks to load), so
/// it runs only on iOS 27 simulators; the app under test stays on iOS 17.
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

    @MainActor
    func test_audioSearch_findsASeededBook_andPlayAudioPlaysIt() async throws {
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

    /// Siri passes the request as spoken: an article, the author, a trailing "book" (#201). The
    /// seeded library also holds "Seeded Plain Book" by the same author, which must not match.
    @MainActor
    func test_audioSearch_withExtraWords_findsOnlyThatBook() async throws {
        app.launchArguments = [LaunchArgument.seedLibrary]
        app.launch()
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 20))

        let definitions = IntentDefinitions(bundleIdentifier: "com.edyuto.Abbay")
        let result = try await definitions.valueQueries["AudioDomainBookQuery"]
            .values(for: AudioSearch(criteria: .searchQuery("the seeded chaptered book by Seed Author")))
        XCTAssertEqual(result.items.count, 1)
        let book = try result.items[0].as(definitions.entities["AudioDomainBookEntity"])
        let title: String = try book.title
        XCTAssertEqual(title, "Seeded Chaptered Book")
    }

    /// An author-only request (#207): "play something by Seed Author" carries on with the last book
    /// played by that author (both seeded books are theirs, so the one just played is the answer),
    /// in en and pt-BR, and an author with no book in the library gets nothing rather than any book.
    /// Offering all of an author's books when none was played last is unit-tested
    /// (`SpokenAuthorMatchingTests`): the last-played pointer outlives a launch, so a UI test can't
    /// start from none.
    @MainActor
    func test_audioSearch_authorOnly_carriesOnWithThatAuthorsLastPlayedBook() async throws {
        app.launchArguments = [LaunchArgument.seedLibrary]
        app.launch()
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 20))

        let definitions = IntentDefinitions(bundleIdentifier: "com.edyuto.Abbay")
        let query = definitions.valueQueries["AudioDomainBookQuery"]
        let plain = try await query.values(for: AudioSearch(criteria: .searchQuery("Seeded Plain Book")))
        XCTAssertEqual(plain.items.count, 1)
        let plainBook = try plain.items[0].as(definitions.entities["AudioDomainBookEntity"])
        try await definitions.intents["PlayAudioDomainIntent"].makeIntent(audioEntity: plainBook).run()
        let bar = element(AccessibilityID.MiniPlayer.bar)
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "the intent didn't load the book")
        XCTAssertTrue(bar.label.contains("Seeded Plain Book"), "unexpected bar \"\(bar.label)\"")

        for spoken in ["something by Seed Author", "um livro do Seed Author", "seed author"] {
            let result = try await query.values(for: AudioSearch(criteria: .searchQuery(spoken)))
            XCTAssertEqual(result.items.count, 1, spoken)
            let book = try result.items[0].as(definitions.entities["AudioDomainBookEntity"])
            let title: String = try book.title
            let author: String = try book.author
            XCTAssertEqual(title, "Seeded Plain Book", spoken)
            XCTAssertEqual(author, "Seed Author", spoken)
        }

        let nobody = try await query.values(for: AudioSearch(criteria: .searchQuery("something by Nobody Else")))
        XCTAssertEqual(nobody.items.count, 0)
    }

    @MainActor
    func test_audioSearch_withNoTitle_offersTheLibrary() async throws {
        app.launchArguments = [LaunchArgument.seedLibrary]
        app.launch()
        XCTAssertTrue(element(AccessibilityID.Library.list).waitForExistence(timeout: 20))

        let definitions = IntentDefinitions(bundleIdentifier: "com.edyuto.Abbay")
        let result = try await definitions.valueQueries["AudioDomainBookQuery"]
            .values(for: AudioSearch(criteria: .unspecified))
        XCTAssertGreaterThanOrEqual(result.items.count, 2, "the seeded library has at least two books")
    }
}
