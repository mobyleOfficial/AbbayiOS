//
//  PlayerViewModelChapterTapTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// #166's owner decision: tapping a chapter always plays that chapter of the book the player
/// shows, even paused or with another book loaded, and never seeks the loaded book on another's
/// behalf.
@MainActor
final class PlayerViewModelChapterTapTests: XCTestCase {
    private let otherURL = URL(string: "file:///vm/other.m4b")

    private func otherBook(currentTime: Double) -> AudioModel {
        var book = ViewModelSupport.chaptered(currentTime: currentTime)
        book.title = "Other"
        book.url = otherURL
        return book
    }

    private func libriVoxBook() -> AudioModel {
        var book = ViewModelSupport.chaptered()
        book.librivoxID = "42"
        book.url = LibriVoxIdentity.bookURL(id: "42")
        return book
    }

    private func loadedState(_ book: AudioModel, isPlaying: Bool = true) -> PlaybackState {
        let state = PlaybackState()
        state.setLoadedBook(book)
        state.setIsPlaying(isPlaying)
        return state
    }

    /// Paused is no exception: the loaded book seeks to the chapter's start and plays.
    func test_selectChapter_shownBookLoadedAndPaused_seeksToTheChapterAndPlays() {
        let book = ViewModelSupport.chaptered()
        let state = loadedState(book, isPlaying: false)
        let player = MockPlayer()
        player.url = book.url
        let sut = PlayerViewModel(book, state: state, player: player, downloads: nil)

        sut.selectChapter(2)
        sut.selectChapter(9)

        XCTAssertEqual(player.playChapterCalls, [2], "seeks to chapter three's start and plays; 9 is out of range")
        XCTAssertEqual(player.playCalls.map(\.url), [], "the loaded book is resumed in place, not reloaded")
    }

    /// Another book is loaded: the tap loads the shown book at the chapter's start (never started),
    /// then seeks it.
    /// It must never seek the loaded book on the shown one's behalf (the wrong chapter of the
    /// wrong book).
    func test_selectChapter_anotherBookLoaded_switchesToTheShownBookThenSeeks() {
        let loaded = ViewModelSupport.chaptered()
        let player = MockPlayer()
        player.url = loaded.url
        let shown = otherBook(currentTime: 250)
        let sut = PlayerViewModel(shown, state: loadedState(loaded), player: player, downloads: nil)

        sut.selectChapter(1)

        XCTAssertEqual(player.playCalls.map(\.url), [otherURL], "the shown book is loaded first")
        XCTAssertEqual(player.playCalls.first?.currentTime, 100, "at the chapter's start, not its saved 250 s")
        XCTAssertEqual(player.playChapterCalls, [1], "then the chapter is played, in the shown book")
        XCTAssertEqual(player.seekSeconds, [])
    }

    /// #299: the shown book is loaded where the tapped chapter was left, not at the chapter's start,
    /// so it plays on from there with no jump back once loaded.
    func test_selectChapter_anotherBookLoaded_loadsTheShownBookWhereTheChapterWasLeft() {
        let loaded = ViewModelSupport.chaptered()
        let player = MockPlayer()
        player.url = loaded.url
        player.resumeTimes[1] = 160
        let shown = otherBook(currentTime: 250)
        let sut = PlayerViewModel(shown, state: loadedState(loaded), player: player, downloads: nil)

        sut.selectChapter(1)

        XCTAssertEqual(player.playCalls.first?.currentTime, 160, "chapter two, 60 s in")
        XCTAssertEqual(player.playChapterCalls, [1])
    }

    /// The shown book can't be played (not downloaded and offline, or its file is gone): the tap
    /// does what Play does, so the player reports why, and nothing seeks the loaded book.
    func test_selectChapter_shownBookCannotPlay_doesWhatPlayDoes_andLeavesTheLoadedBookAlone() {
        let loaded = ViewModelSupport.chaptered()
        let player = MockPlayer()
        player.url = loaded.url
        player.loadsOnPlay = false
        let shown = libriVoxBook()
        let sut = PlayerViewModel(shown, state: loadedState(loaded), player: player, downloads: nil)

        sut.selectChapter(1)

        XCTAssertEqual(player.playCalls.map(\.url), [shown.url])
        XCTAssertEqual(player.playChapterCalls, [], "the loaded book is not moved on the shown book's behalf")
        XCTAssertEqual(player.seekSeconds, [])
        XCTAssertEqual(player.url, loaded.url)
    }
}
