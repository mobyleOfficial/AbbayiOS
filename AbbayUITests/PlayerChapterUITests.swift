//
//  PlayerChapterUITests.swift
//  AbbayUITests
//

import XCTest

/// A chapter tap with real audio (`-seedPlayableBook`, the four-chapter Christmastide m4b saved
/// 200 s in, in chapter 2), #166's owner decision. The test pauses at the end: the book makes sound.
///
/// #151 (two quick *Next chapter*s) has no UI test here: two accessibility actions sent back to
/// back are slow enough for the first seek to land, so such a test passes without the fix. It is
/// proven by `PlayerChapterNavigationTests`, which plays the same m4b.
extension MiniPlayerUITests {
    private var chapterBar: XCUIElement { element(AccessibilityID.MiniPlayer.bar) }

    private func waitForLabel(
        of element: XCUIElement,
        _ matches: (String) -> Bool,
        timeout: TimeInterval = 10
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !matches(element.label), Date() < deadline {
            usleep(100_000)
        }
        return matches(element.label)
    }

    private func pauseFromBar() {
        let playPause = element(AccessibilityID.MiniPlayer.playPause)
        if playPause.waitForExistence(timeout: 5), playPause.label == "Pause" {
            playPause.tap()
        }
    }

    /// Nothing loaded and nothing playing: opening the playable book and tapping its fourth chapter
    /// loads it and plays from that chapter, not from the saved 200 s (chapter 2).
    func test_chapterTap_bookNotLoaded_playsThatChapter() throws {
        launch([LaunchArgument.seedLibrary, LaunchArgument.seedPlayableBook])
        assertResolves(AccessibilityID.Library.list)
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Playable Book"), "no playable seed")
        element(AccessibilityID.Element.title(AccessibilityID.Library.row(index))).tap()
        waitForPlayerToArrive()
        XCTAssertEqual(transportPlay.label, "Play", "the shown book should start paused")

        let chapter = element(AccessibilityID.Player.chapter(3))
        XCTAssertTrue(chapter.waitForExistence(timeout: 5))
        chapter.tap()

        XCTAssertTrue(waitForLabel(of: transportPlay) { $0 == "Pause" }, "the tap did not start playback")
        element(AccessibilityID.Player.close).tap()
        XCTAssertTrue(chapterBar.waitForExistence(timeout: 15))
        XCTAssertTrue(
            waitForLabel(of: chapterBar) { $0.contains("Chapter 4") },
            "not in chapter 4: \"\(chapterBar.label)\""
        )
        pauseFromBar()
    }
}
