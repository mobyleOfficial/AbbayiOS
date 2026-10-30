//
//  ReadAlongFullScreenTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The read-along text full screen (#192): shown over a presented player only, and ended with it,
/// with another book, with a change of split, and when the screen follows another loaded book.
@MainActor
final class ReadAlongFullScreenTests: XCTestCase {
    private let other = AudioModel(title: "Other", url: URL(string: "file:///vm/other.m4b"))

    private func fullScreen(for book: AudioModel, slot: ReadAlongSessionSlot? = nil) -> ReadAlongFullScreen {
        ReadAlongFullScreen(
            model: PlayerViewModel(book, state: PlaybackState(), player: nil, downloads: nil),
            scrub: PlayerScrub(),
            slot: slot ?? ReadAlongSessionSlot()
        )
    }

    /// The text goes full screen only over a presented player: there is nothing to expand from
    /// otherwise.
    func test_readAlongFullScreen_needsAPresentedBook() {
        let sut = PlayerPresentation()
        let book = ViewModelSupport.chaptered()

        sut.showReadAlongFullScreen(fullScreen(for: book))
        XCTAssertNil(sut.readAlongFullScreen, "no player, no full screen")

        sut.open(book, animated: false)
        sut.showReadAlongFullScreen(fullScreen(for: book))
        XCTAssertNotNil(sut.readAlongFullScreen)
        sut.endReadAlongFullScreen()
        XCTAssertNil(sut.readAlongFullScreen, "collapsed")
    }

    /// Closing the player ends it at once, not once the collapse lands: the text would float over
    /// a closing player.
    func test_readAlongFullScreen_endsAsThePlayerCloses() {
        let sut = PlayerPresentation()
        let book = ViewModelSupport.chaptered()
        sut.open(book, animated: false)
        sut.showReadAlongFullScreen(fullScreen(for: book))

        sut.close(animated: true)

        XCTAssertNil(sut.readAlongFullScreen)
    }

    /// Another book presented (its own screen, its own session) ends it; the same book again doesn't.
    func test_readAlongFullScreen_endsWhenAnotherBookIsPresented() {
        let sut = PlayerPresentation()
        let book = ViewModelSupport.chaptered()
        sut.open(book, animated: false)
        sut.showReadAlongFullScreen(fullScreen(for: book))

        sut.open(book, animated: false)
        XCTAssertNotNil(sut.readAlongFullScreen, "the same book")
        sut.open(other, animated: false)
        XCTAssertNil(sut.readAlongFullScreen, "book A's text over book B's player")
    }

    /// A fold or a resize swaps the full-screen player for the pane (or back): another screen,
    /// with another session, so the full screen of the old one ends.
    func test_readAlongFullScreen_endsWhenTheSplitChanges() {
        let sut = PlayerPresentation()
        let book = ViewModelSupport.chaptered()
        sut.open(book, animated: false)
        sut.showReadAlongFullScreen(fullScreen(for: book))

        sut.layoutChanged(usesPanes: false)
        XCTAssertNotNil(sut.readAlongFullScreen, "no change")
        sut.layoutChanged(usesPanes: true)
        XCTAssertNil(sut.readAlongFullScreen)
    }

    /// A player screen that leaves ends only its own full screen.
    func test_endReadAlongFullScreen_ofASlot_endsOnlyThatScreens() {
        let sut = PlayerPresentation()
        let book = ViewModelSupport.chaptered()
        let slot = ReadAlongSessionSlot()
        sut.open(book, animated: false)
        sut.showReadAlongFullScreen(fullScreen(for: book, slot: slot))

        sut.endReadAlongFullScreen(of: ReadAlongSessionSlot())
        XCTAssertNotNil(sut.readAlongFullScreen, "another screen's slot")
        sut.endReadAlongFullScreen(of: slot)
        XCTAssertNil(sut.readAlongFullScreen)
    }

    /// The screen follows the loaded book after a switch (Siri, CarPlay): the full screen opened on
    /// book A no longer shows its text once the screen shows book B.
    func test_readAlongFullScreen_isNoLongerItsBook_onceTheScreenFollowsAnother() {
        let book = ViewModelSupport.chaptered()
        let state = PlaybackState()
        state.setLoadedBook(book)
        let model = PlayerViewModel(book, state: state, player: nil, downloads: nil)
        let sut = ReadAlongFullScreen(model: model, scrub: PlayerScrub(), slot: ReadAlongSessionSlot())
        XCTAssertTrue(sut.showsItsBook)

        state.setLoadedBook(other)

        XCTAssertEqual(model.book.url, other.url, "the screen follows the loaded book")
        XCTAssertFalse(sut.showsItsBook)
    }
}
