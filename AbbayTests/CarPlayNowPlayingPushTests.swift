//
//  CarPlayNowPlayingPushTests.swift
//  AbbayTests
//

@testable import Abbay
import CarPlay
import XCTest

/// Covers the push decision only. The delegate itself has no injection seam yet (#96), so the
/// rule is extracted as a pure function and tested directly.
final class CarPlayNowPlayingPushTests: XCTestCase {
    private let nowPlaying = CPNowPlayingTemplate.shared

    private func listTemplate(_ title: String) -> CPListTemplate {
        CPListTemplate(title: title, sections: [])
    }

    func test_emptyStack_needsPush() {
        XCTAssertTrue(
            CarPlaySceneDelegate.needsNowPlayingPush(templates: [], nowPlaying: nowPlaying)
        )
    }

    func test_libraryOnly_needsPush() {
        XCTAssertTrue(
            CarPlaySceneDelegate.needsNowPlayingPush(
                templates: [listTemplate("Your Audiobooks")],
                nowPlaying: nowPlaying
            ),
            "playback started outside CarPlay must bring the now-playing template up"
        )
    }

    func test_nowPlayingAlreadyTop_doesNotPushAgain() {
        XCTAssertFalse(
            CarPlaySceneDelegate.needsNowPlayingPush(
                templates: [listTemplate("Your Audiobooks"), nowPlaying],
                nowPlaying: nowPlaying
            ),
            "a CarPlay tap publishes before it pushes, so an unguarded push would duplicate"
        )
    }

    func test_chapterListAboveNowPlaying_doesNotPush() {
        XCTAssertFalse(
            CarPlaySceneDelegate.needsNowPlayingPush(
                templates: [listTemplate("Your Audiobooks"), nowPlaying, listTemplate("Chapter selection")],
                nowPlaying: nowPlaying
            ),
            "a track change must not yank the user out of the chapter list"
        )
    }

    func test_identityNotEquality_decidesPresence() {
        XCTAssertTrue(
            CarPlaySceneDelegate.needsNowPlayingPush(
                templates: [listTemplate("Your Audiobooks"), listTemplate("Your Audiobooks")],
                nowPlaying: nowPlaying
            ),
            "two distinct templates must never be mistaken for the shared now-playing instance"
        )
    }
}
