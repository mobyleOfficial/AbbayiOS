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

    // MARK: - Start over (#299)

    /// The loaded book goes back to the chapter's start, whatever was saved for it, and plays.
    func test_restartChapter_shownBookLoaded_seeksToTheChaptersStartAndPlays() {
        let book = ViewModelSupport.chaptered(currentTime: 150)
        let player = MockPlayer()
        player.url = book.url
        player.resumeTimes[1] = 150
        let sut = PlayerViewModel(book, state: loadedState(book), player: player, downloads: nil)

        sut.restartChapter(1)
        sut.restartChapter(9)

        XCTAssertEqual(player.seekSeconds, [100], "chapter two's start, not where it was left; 9 is out of range")
        XCTAssertEqual(player.playChapterCalls, [1])
        XCTAssertEqual(player.playCalls.map(\.url), [], "not reloaded")
    }

    func test_restartChapter_anotherBookLoaded_loadsTheShownBookAtTheChaptersStart() {
        let loaded = ViewModelSupport.chaptered()
        let player = MockPlayer()
        player.url = loaded.url
        player.resumeTimes[1] = 160
        let shown = otherBook(currentTime: 160)
        let sut = PlayerViewModel(shown, state: loadedState(loaded), player: player, downloads: nil)

        sut.restartChapter(1)

        XCTAssertEqual(player.playCalls.map(\.url), [otherURL])
        XCTAssertEqual(player.playCalls.first?.currentTime, 100, "the start, not the 160 s it was left at")
        XCTAssertEqual(player.playChapterCalls, [1])
        XCTAssertEqual(player.seekSeconds, [], "the loaded book is never moved on the shown one's behalf")
    }

    func test_restartChapter_shownBookCannotPlay_movesNothing() {
        let loaded = ViewModelSupport.chaptered()
        let player = MockPlayer()
        player.url = loaded.url
        player.loadsOnPlay = false
        let sut = PlayerViewModel(libriVoxBook(), state: loadedState(loaded), player: player, downloads: nil)

        sut.restartChapter(1)

        XCTAssertEqual(player.playChapterCalls, [])
        XCTAssertEqual(player.seekSeconds, [])
    }

    // MARK: - Resume prompt (#299)

    /// A tap that resumes partway in returns the prompt: which book and chapter, and where.
    func test_selectChapter_resumedPartwayIn_returnsThePrompt() throws {
        let loaded = ViewModelSupport.chaptered()
        let player = MockPlayer()
        player.url = loaded.url
        player.resumeTimes[1] = 160
        let shown = otherBook(currentTime: 250)
        let sut = PlayerViewModel(shown, state: loadedState(loaded), player: player, downloads: nil)

        let prompt = try XCTUnwrap(sut.selectChapter(1))

        XCTAssertEqual(prompt.bookURL, otherURL)
        XCTAssertEqual(prompt.chapterIndex, 1)
        XCTAssertEqual(prompt.time, 160)
    }

    func test_selectChapter_fromItsStart_returnsNoPrompt() {
        let book = ViewModelSupport.chaptered()
        let player = MockPlayer()
        player.url = book.url
        let sut = PlayerViewModel(book, state: loadedState(book), player: player, downloads: nil)

        XCTAssertNil(sut.selectChapter(2), "never started: from its start, nothing to offer")
        player.resumeTimes[2] = 200.5
        XCTAssertNil(sut.selectChapter(2), "half a second in reads as its start")
    }

    /// The chapter already playing plays on: nothing resumed, so no prompt.
    func test_selectChapter_theChapterPlaying_returnsNoPrompt() {
        let book = ViewModelSupport.chaptered(currentTime: 150)
        let player = MockPlayer()
        player.url = book.url
        player.currentTime = 150
        player.resumeTimes[1] = 140
        let sut = PlayerViewModel(book, state: loadedState(book), player: player, downloads: nil)

        XCTAssertNil(sut.selectChapter(1))
        XCTAssertEqual(player.playChapterCalls, [1])
    }

    func test_selectChapter_cannotLoad_returnsNoPrompt() {
        let loaded = ViewModelSupport.chaptered()
        let player = MockPlayer()
        player.url = loaded.url
        player.loadsOnPlay = false
        player.resumeTimes[1] = 160
        let sut = PlayerViewModel(libriVoxBook(), state: loadedState(loaded), player: player, downloads: nil)

        XCTAssertNil(sut.selectChapter(1))
    }

    /// The chapter playing but listened to its end isn't "playing on": the tap starts it over, so
    /// there's nothing resumed to offer.
    func test_selectChapter_theChapterPlayingAtItsEnd_playsItAgain_withNoPrompt() {
        let book = ViewModelSupport.chaptered(currentTime: 398)
        let player = MockPlayer()
        player.url = book.url
        player.currentTime = 398
        let sut = PlayerViewModel(book, state: loadedState(book), player: player, downloads: nil)

        XCTAssertNil(sut.selectChapter(2))
        XCTAssertEqual(player.playChapterCalls, [2])
    }
}
