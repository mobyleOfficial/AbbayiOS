//
//  PlayerViewModelTests.swift
//  AbbayTests
//

@testable import Abbay
import Observation
import XCTest

/// `PlayerViewModel` adapts the app-wide stores for the details screen. It holds no player
/// subscriptions: for the loaded book it reads `PlaybackState` and (in the screen's leaves only)
/// `PlaybackClock`; for any other book, the book's saved fields. Downloads come from the book's
/// `BookDownloadEntry`.
@MainActor
final class PlayerViewModelTests: XCTestCase {
    private let otherURL = URL(string: "file:///vm/other.m4b")

    private func otherBook(currentTime: Double = 250) -> AudioModel {
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

    // MARK: - Which book, which time

    func test_presentedLoadedBook_readsPlaybackStores() {
        let book = ViewModelSupport.chaptered(currentTime: 10)
        let state = loadedState(book)
        let clock = PlaybackClock()
        clock.update(bookTime: 150, currentChapter: 1)

        let sut = PlayerViewModel(book, state: state, player: MockPlayer(), downloads: nil)

        XCTAssertTrue(sut.isLoaded)
        XCTAssertTrue(sut.isPlaying)
        XCTAssertEqual(sut.bookTime(in: clock), 150, "the clock, not the saved 10 s")
        XCTAssertEqual(sut.currentChapter(in: clock), 1)
        state.setIsPlaying(false)
        XCTAssertFalse(sut.isPlaying, "pause shows at once, from PlaybackState")
    }

    func test_presentedOtherBook_showsSavedPosition_andPlayLoadsIt() {
        let state = loadedState(ViewModelSupport.chaptered())
        let clock = PlaybackClock()
        clock.update(bookTime: 150, currentChapter: 1)
        let player = MockPlayer()
        let other = otherBook(currentTime: 250)

        let sut = PlayerViewModel(other, state: state, player: player, downloads: nil)

        XCTAssertFalse(sut.isLoaded)
        XCTAssertFalse(sut.isPlaying, "another book playing doesn't make this one playing")
        XCTAssertEqual(sut.book.url, otherURL)
        XCTAssertEqual(sut.bookTime(in: clock), 250, "the book's saved position")
        XCTAssertEqual(sut.currentChapter(in: clock), 2)
        // The transport must not move the loaded book while another one is shown.
        sut.forward(withSeconds: 15)
        sut.backward(withSeconds: 15)
        sut.seek(10)
        sut.pause()
        XCTAssertEqual(player.forwardSeconds, [])
        XCTAssertEqual(player.backwardSeconds, [])
        XCTAssertEqual(player.seekSeconds, [])
        XCTAssertEqual(player.pauseCallCount, 0)

        sut.play()

        XCTAssertEqual(player.playCalls.map(\.url), [otherURL])
    }

    /// Siri or CarPlay can switch books while the details screen of the loaded book is open (even
    /// mid-drag): the screen follows the loaded book, and its time comes from the clock.
    func test_loadedBookChangesMidDrag_overlayShowsNewBook() {
        let book = ViewModelSupport.chaptered()
        let state = loadedState(book)
        let clock = PlaybackClock()
        let sut = PlayerViewModel(book, state: state, player: MockPlayer(), downloads: nil)
        XCTAssertEqual(sut.book.url, book.url)

        state.setLoadedBook(otherBook(currentTime: 0))
        clock.update(bookTime: 77, currentChapter: 0)

        XCTAssertEqual(sut.book.url, otherURL)
        XCTAssertEqual(sut.book.title, "Other")
        XCTAssertTrue(sut.isLoaded)
        XCTAssertEqual(sut.bookTime(in: clock), 77)
    }

    /// Pressing Play on another book's screen loads it, and from then on the screen follows it.
    func test_playingThePresentedBook_followsItAsTheLoadedBook() {
        let state = loadedState(ViewModelSupport.chaptered())
        let player = MockPlayer()
        let sut = PlayerViewModel(otherBook(), state: state, player: player, downloads: nil)

        sut.play()
        state.setLoadedBook(otherBook())

        XCTAssertTrue(sut.isLoaded)
        sut.forward(withSeconds: 15)
        XCTAssertEqual(player.forwardSeconds, [15])
    }

    /// Ruling 14: the overlay draws the growing cover and the tint from the same model the details
    /// content uses, one per presented book, so after a switch to B they show B's art, not A's.
    func test_detailsModels_oneModelPerBook_followingTheLoadedBook() {
        let book = ViewModelSupport.chaptered()
        let state = loadedState(book)
        let models = PlayerDetailsModels()

        let model = models.model(for: book, presentationID: 1, state: state, player: nil, downloads: nil)
        XCTAssertEqual(model.book.url, book.url)
        var switched = otherBook()
        switched.imageData = Data([1, 2, 3])
        state.setLoadedBook(switched)

        let again = models.model(for: book, presentationID: 1, state: state, player: nil, downloads: nil)
        XCTAssertTrue(again === model, "the same model for the same presented book")
        XCTAssertEqual(again.book.url, otherURL)
        XCTAssertEqual(again.book.imageData, Data([1, 2, 3]))
        let next = models.model(for: otherBook(), presentationID: 1, state: state, player: nil, downloads: nil)
        XCTAssertFalse(next === model, "another presented book gets its own model")
    }

    /// N2: the model lives for one presentation. Present A while A is loaded (the follow latch
    /// sets), close, B gets loaded, present A again: A's saved fields, and Play loads A.
    func test_detailsModels_doNotCarryAcrossPresentations() {
        let bookA = ViewModelSupport.chaptered(currentTime: 30)
        let state = loadedState(bookA)
        let player = MockPlayer()
        let presentation = PlayerPresentation(playback: state)
        let models = PlayerDetailsModels()
        let clock = PlaybackClock()
        clock.update(bookTime: 150, currentChapter: 1)

        presentation.open(bookA, animated: false)
        let first = models.model(
            for: bookA,
            presentationID: presentation.presentationID,
            state: state,
            player: player,
            downloads: nil
        )
        XCTAssertTrue(first.isLoaded)
        presentation.close(animated: false)
        state.setLoadedBook(otherBook())
        presentation.open(bookA, animated: false)

        let second = models.model(
            for: bookA,
            presentationID: presentation.presentationID,
            state: state,
            player: player,
            downloads: nil
        )

        XCTAssertEqual(second.book.url, bookA.url, "A's screen, not the loaded B")
        XCTAssertFalse(second.isLoaded)
        XCTAssertEqual(second.bookTime(in: clock), 30, "A's saved position")
        second.play()
        XCTAssertEqual(player.playCalls.last?.url, bookA.url, "Play loads A, it doesn't resume B")
    }

    // MARK: - The hard rule

    func test_playerViewModel_makesNoPlayerSubscriptions() {
        let player = CountingMockPlayer()
        let book = ViewModelSupport.chaptered()
        let state = loadedState(book)
        let clock = PlaybackClock()
        let store = DownloadStateStore(downloads: MockBookDownloadManager())

        let models = (0..<20).map { index -> PlayerViewModel in
            var presented = book
            if index.isMultiple(of: 2) { presented.url = URL(string: "file:///vm/book\(index).m4b") }
            let model = PlayerViewModel(presented, state: state, player: player, downloads: store)
            _ = model.book
            _ = model.bookTime(in: clock)
            _ = model.downloadEntry
            model.play()
            model.pause()
            return model
        }

        XCTAssertEqual(player.urlSubscriptionCount, 0)
        XCTAssertEqual(player.timeSubscriptionCount, 0)
        XCTAssertEqual(player.playingSubscriptionCount, 0)
        withExtendedLifetime(models) {}
    }

    /// What the details screen's chrome reads (book, playing state, download entry) never touches
    /// the clock: only its timeline and chapter list leaves do.
    func test_detailsChrome_readsNoClockProperty() {
        let book = ViewModelSupport.chaptered()
        let state = loadedState(book)
        let clock = PlaybackClock()
        let sut = PlayerViewModel(book, state: state, player: MockPlayer(), downloads: nil)
        var fired = false

        withObservationTracking({
            _ = sut.book
            _ = sut.isLoaded
            _ = sut.isPlaying
            _ = sut.downloadEntry
        }, onChange: { fired = true })
        for tick in 1...5 { clock.update(bookTime: Double(tick * 90), currentChapter: tick % 3) }

        XCTAssertFalse(fired)
    }

    /// The chapter list leaf depends on the chapter, not on every tick.
    func test_currentChapter_doesNotDependOnBookTime() {
        let book = ViewModelSupport.chaptered()
        let sut = PlayerViewModel(book, state: loadedState(book), player: MockPlayer(), downloads: nil)
        let clock = PlaybackClock()
        var fired = false

        withObservationTracking({ _ = sut.currentChapter(in: clock) }, onChange: { fired = true })
        clock.update(bookTime: 20, currentChapter: 0)
        clock.update(bookTime: 30, currentChapter: 0)

        XCTAssertFalse(fired)
    }

    // MARK: - Transport

    func test_transport_delegatesForTheLoadedBook() {
        let book = ViewModelSupport.chaptered()
        let player = MockPlayer()
        let sut = PlayerViewModel(book, state: loadedState(book), player: player, downloads: nil)

        sut.play()
        sut.pause()
        sut.forward(withSeconds: 15)
        sut.backward(withSeconds: 30)
        sut.seek(120)

        XCTAssertEqual(player.playCalls.map(\.url), [book.url])
        XCTAssertEqual(player.pauseCallCount, 1)
        XCTAssertEqual(player.forwardSeconds, [15])
        XCTAssertEqual(player.backwardSeconds, [30])
        XCTAssertEqual(player.seekSeconds, [120])
    }

    // MARK: - Download state

    func test_downloadEntry_nilForImportedBook() {
        let store = DownloadStateStore(downloads: MockBookDownloadManager())
        let book = ViewModelSupport.chaptered()

        let sut = PlayerViewModel(book, state: PlaybackState(), player: nil, downloads: store)

        XCTAssertNil(sut.downloadEntry)
    }

    func test_isHeldByLowDataMode_forAWiFiOnlyBookWhileLowDataModeIsOn() {
        let manager = MockBookDownloadManager()
        let path = FakeNetworkPath()
        let store = DownloadStateStore(downloads: manager, path: path)
        var wifiOnly = libriVoxBook()
        wifiOnly.allowsCellularDownload = false
        var cellular = libriVoxBook()
        cellular.allowsCellularDownload = true
        manager.statesSubject.send(["42": BookDownloadState(chapters: [.waiting], expectedBytes: [1], isPaused: false)])
        path.isLowDataMode = true

        let viewModel = { (book: AudioModel) in
            PlayerViewModel(book, state: PlaybackState(), player: nil, downloads: store)
        }
        XCTAssertTrue(viewModel(wifiOnly).isHeldByLowDataMode)
        XCTAssertFalse(viewModel(cellular).isHeldByLowDataMode)
        XCTAssertFalse(
            PlayerViewModel(ViewModelSupport.chaptered(), state: PlaybackState(), player: nil, downloads: store)
                .isHeldByLowDataMode
        )
    }

    func test_downloadEntry_isTheBooksStoreEntry() {
        let manager = MockBookDownloadManager()
        let store = DownloadStateStore(downloads: manager)
        let book = libriVoxBook()
        let running = BookDownloadState(
            chapters: [.downloaded, .downloading(fraction: 0.5), .waiting],
            expectedBytes: [],
            isPaused: false
        )

        let sut = PlayerViewModel(book, state: PlaybackState(), player: nil, downloads: store)
        manager.statesSubject.send(["42": running])

        XCTAssertTrue(sut.downloadEntry === store.entry(for: "42"))
        XCTAssertEqual(sut.downloadEntry?.state, running)
        manager.statesSubject.send([
            "42": BookDownloadState(chapters: [.downloaded, .downloaded], expectedBytes: [], isPaused: false)
        ])
        XCTAssertNil(sut.downloadEntry?.state, "complete: no per-chapter status, as before")
    }

    func test_retryChapter_forwardsToTheDownloadManager() {
        let manager = MockBookDownloadManager()
        let store = DownloadStateStore(downloads: manager)
        let sut = PlayerViewModel(libriVoxBook(), state: PlaybackState(), player: nil, downloads: store)

        sut.retryChapter(2)

        XCTAssertEqual(manager.retried.map(\.chapterIndex), [2])
        XCTAssertEqual(manager.retried.map(\.bookID), ["42"])
    }

    func test_retryChapter_importedBook_doesNothing() {
        let manager = MockBookDownloadManager()
        let store = DownloadStateStore(downloads: manager)
        let sut = PlayerViewModel(ViewModelSupport.chaptered(), state: PlaybackState(), player: nil, downloads: store)

        sut.retryChapter(0)

        XCTAssertTrue(manager.retried.isEmpty)
    }

    // MARK: - Speed

    func test_setSpeed_onTheLoadedBook_goesToThePlayer() {
        let book = ViewModelSupport.chaptered()
        let player = MockPlayer()
        let settings = AppSettings(store: InMemoryKeyValueStore())
        let sut = PlayerViewModel(book, state: loadedState(book), player: player, downloads: nil)

        sut.setSpeed(1.5, in: settings)

        XCTAssertEqual(player.rateCalls, [1.5], "the player applies it at once and saves it")
    }

    /// Another book's transport does nothing until it plays; its speed is just remembered.
    func test_setSpeed_onAnotherBook_isRememberedForIt_withoutTouchingThePlayer() {
        let player = MockPlayer()
        let settings = AppSettings(store: InMemoryKeyValueStore())
        let state = loadedState(ViewModelSupport.chaptered())
        let sut = PlayerViewModel(otherBook(), state: state, player: player, downloads: nil)

        sut.setSpeed(2, in: settings)

        XCTAssertTrue(player.rateCalls.isEmpty)
        XCTAssertEqual(settings.speed(for: otherURL), 2)
        XCTAssertEqual(sut.speed(in: settings), 2)
    }

    func test_speed_ofABookWithoutItsOwn_isTheDefault() {
        let settings = AppSettings(store: InMemoryKeyValueStore())
        settings.defaultSpeed = 1.25
        let sut = PlayerViewModel(otherBook(), state: PlaybackState(), player: nil, downloads: nil)

        XCTAssertEqual(sut.speed(in: settings), 1.25)
    }
}
