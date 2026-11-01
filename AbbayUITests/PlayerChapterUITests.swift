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

        openChaptersPanel()
        let chapter = element(AccessibilityID.Player.chapter(3))
        // On a shorter screen (the iPhone Duo, the iOS 27.1 runtime's only device) the fourth row
        // can start below the panel's fold, and the lazy list hasn't built it yet: scroll to it.
        if !chapter.waitForExistence(timeout: 5) {
            element(AccessibilityID.Player.chapter(0)).swipeUp()
        }
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

    /// The player's elapsed time in seconds, from its `m:ss` label (the remaining one has a minus).
    private func elapsedSeconds() -> Int? {
        let clock = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+:[0-9]{2}$")).firstMatch
        guard clock.waitForExistence(timeout: 5) else { return nil }
        let parts = clock.label.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : nil
    }

    private func tapChapter(_ index: Int) {
        openChaptersPanel()
        let chapter = element(AccessibilityID.Player.chapter(index))
        if !chapter.waitForExistence(timeout: 5) {
            element(AccessibilityID.Player.chapter(0)).swipeUp()
        }
        XCTAssertTrue(chapter.waitForExistence(timeout: 5), "no row for chapter \(index + 1)")
        chapter.tap()
    }

    /// #299: a chapter left for another one resumes where it was left. The book plays from 200 s,
    /// 56 s into chapter 2 (which starts at 2:24); a tap on chapter 4 and back on chapter 2 lands
    /// at 3:20 or a little after, not at 2:24.
    func test_chapterTap_backToAChapterLeft_resumesWhereItWasLeft() throws {
        launch([LaunchArgument.seedLibrary, LaunchArgument.seedPlayableBook])
        assertResolves(AccessibilityID.Library.list)
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Playable Book"), "no playable seed")
        element(AccessibilityID.Element.title(AccessibilityID.Library.row(index))).tap()
        waitForPlayerToArrive()

        transportPlay.tap()
        XCTAssertTrue(waitForLabel(of: transportPlay) { $0 == "Pause" }, "Play did not start playback")
        sleep(2)

        tapChapter(3)
        XCTAssertTrue(waitForLabel(of: transportPlay) { $0 == "Pause" })
        let inChapterFour = try XCTUnwrap(elapsedSeconds())
        XCTAssertGreaterThanOrEqual(inChapterFour, 511, "chapter 4 never started, so from its start (8:31)")
        sleep(2)

        tapChapter(1)
        XCTAssertTrue(waitForLabel(of: transportPlay) { $0 == "Pause" })
        let backInChapterTwo = try XCTUnwrap(elapsedSeconds())
        XCTAssertGreaterThanOrEqual(backInChapterTwo, 200, "chapter 2 restarted at 2:24 instead of resuming")
        XCTAssertLessThan(backInChapterTwo, 240, "resumed past where chapter 2 was left")
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "chapter 4 at \(inChapterFour) s, back in chapter 2 at \(backInChapterTwo) s"
        evidence.lifetime = .keepAlways
        add(evidence)

        transportPlay.tap()
    }

    /// #299: a chapter tap that resumed partway in shows "Resumed at …" with *Start over*, which
    /// plays the chapter from its beginning. The book plays from 3:20, in chapter 2 (starts 2:24).
    func test_resumePrompt_startOver_playsTheChapterFromItsStart() throws {
        launch([LaunchArgument.seedLibrary, LaunchArgument.seedPlayableBook])
        assertResolves(AccessibilityID.Library.list)
        let index = try XCTUnwrap(rowIndex(titled: "Seeded Playable Book"), "no playable seed")
        element(AccessibilityID.Element.title(AccessibilityID.Library.row(index))).tap()
        waitForPlayerToArrive()
        transportPlay.tap()
        XCTAssertTrue(waitForLabel(of: transportPlay) { $0 == "Pause" }, "Play did not start playback")

        tapChapter(3)
        XCTAssertFalse(
            element(AccessibilityID.Player.resumePrompt).waitForExistence(timeout: 2),
            "chapter 4 was never started: it starts at its start, with no prompt"
        )
        tapChapter(1)
        let prompt = element(AccessibilityID.Player.resumePrompt)
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "no prompt after resuming chapter 2")
        XCTAssertTrue(prompt.label.hasPrefix("Resumed at 3:"), "\"\(prompt.label)\"")
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "resume prompt: \(prompt.label)"
        evidence.lifetime = .keepAlways
        add(evidence)

        element(AccessibilityID.Player.resumePromptStartOver).tap()
        XCTAssertTrue(waitForLabel(of: transportPlay) { $0 == "Pause" })
        let restarted = try XCTUnwrap(elapsedSeconds())
        XCTAssertGreaterThanOrEqual(restarted, 144, "before chapter 2's start")
        XCTAssertLessThan(restarted, 160, "not back at chapter 2's start (2:24)")
        XCTAssertFalse(prompt.exists, "Start over dismisses the prompt")

        transportPlay.tap()
    }
}
