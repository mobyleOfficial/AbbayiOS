//
//  MediaViewModelTests.swift
//  AbbayTests
//

@testable import Abbay
import Observation
import XCTest

/// A library row holds no player subscriptions: it reads the slow `PlaybackState`, its own book's
/// download entry, and sends actions straight to the player. Only `RowProgressView`, shown for the
/// loaded book, reads the ticking `PlaybackClock`.
@MainActor
final class MediaViewModelTests: XCTestCase {
    private let otherURL = URL(string: "file:///vm/other.m4b")

    private func libriVoxBook() -> AudioModel {
        var book = ViewModelSupport.chaptered()
        book.librivoxID = "42"
        book.url = LibriVoxIdentity.bookURL(id: "42")
        return book
    }

    private func plainBook(duration: Double = 200, currentTime: Double = 0) -> AudioModel {
        AudioModel(title: "Plain", artist: "Artist", duration: duration, currentTime: currentTime, url: otherURL)
    }

    private func state(_ chapters: [ChapterDownloadState], isPaused: Bool = false) -> BookDownloadState {
        BookDownloadState(chapters: chapters, isPaused: isPaused, fraction: 0.1)
    }

    // MARK: - Actions

    func test_play_callsPlayerWithTheBook() {
        let player = CountingMockPlayer()
        let book = ViewModelSupport.chaptered()
        let model = MediaViewModel(book, player: player, downloads: nil)

        model.play()

        XCTAssertEqual(player.url, book.url)
    }

    func test_pause_callsPlayer() {
        let player = MockPlayer()
        let model = MediaViewModel(ViewModelSupport.chaptered(), player: player, downloads: nil)

        model.pause()

        XCTAssertEqual(player.pauseCallCount, 1)
    }

    func test_toggleDownload_pausesThenResumes() {
        let manager = MockBookDownloadManager()
        let store = DownloadStateStore(downloads: manager)
        let model = MediaViewModel(libriVoxBook(), player: CountingMockPlayer(), downloads: store)
        manager.statesSubject.send(["42": state([.downloading(fraction: 0.1), .waiting])])

        model.toggleDownload()
        manager.statesSubject.send(["42": state([.waiting, .waiting], isPaused: true)])
        model.toggleDownload()

        XCTAssertEqual(manager.paused, ["42"])
        XCTAssertEqual(manager.resumed, ["42"])
    }

    func test_toggleDownload_importedBook_doesNothing() {
        let manager = MockBookDownloadManager()
        let store = DownloadStateStore(downloads: manager)
        let model = MediaViewModel(ViewModelSupport.chaptered(), player: CountingMockPlayer(), downloads: store)

        model.toggleDownload()

        XCTAssertEqual(manager.paused, [])
        XCTAssertEqual(manager.resumed, [])
    }

    /// The hard rule's first half: rows never subscribe to the player, however many there are.
    func test_rowModel_makesNoPlayerSubscriptions() {
        let player = CountingMockPlayer()
        let store = DownloadStateStore(downloads: MockBookDownloadManager())

        let models = (0..<30).map { index -> MediaViewModel in
            var book = ViewModelSupport.chaptered()
            book.url = URL(string: "file:///vm/book\(index).m4b")
            return MediaViewModel(book, player: player, downloads: store)
        }

        XCTAssertEqual(player.urlSubscriptionCount, 0)
        XCTAssertEqual(player.timeSubscriptionCount, 0)
        XCTAssertEqual(player.playingSubscriptionCount, 0)
        withExtendedLifetime(models) {}
    }

    // MARK: - Detail model (what an idle row's body reads)

    /// The hard rule's second half: a row that isn't the loaded one does zero work per tick.
    func test_idleRow_readsNoClockProperty() {
        let playback = PlaybackState()
        let clock = PlaybackClock()
        playback.setLoadedBook(AudioModel(title: "Other", url: otherURL))
        playback.setIsPlaying(true)
        let book = ViewModelSupport.chaptered()
        var fired = false

        withObservationTracking({
            _ = MediaView.DetailModel(book: book, state: playback, entry: nil)
        }, onChange: { fired = true })
        for tick in 1...5 { clock.update(bookTime: Double(tick * 100), currentChapter: tick % 3) }

        XCTAssertFalse(fired)
    }

    /// An idle row doesn't depend on another book's play/pause either: it reads `isPlaying` only
    /// when its own book is the loaded one.
    func test_idleRow_ignoresAnotherBooksPlayPause() {
        let playback = PlaybackState()
        playback.setLoadedBook(AudioModel(title: "Other", url: otherURL))
        let book = ViewModelSupport.chaptered()
        var fired = false

        withObservationTracking({
            _ = MediaView.DetailModel(book: book, state: playback, entry: nil)
        }, onChange: { fired = true })
        playback.setIsPlaying(true)
        playback.setIsPlaying(false)

        XCTAssertFalse(fired)
    }

    /// The playing row's progress sub-view must follow the clock.
    func test_loadedRowProgress_followsTheClock() {
        let clock = PlaybackClock()
        let book = plainBook()
        var fired = false

        withObservationTracking({
            _ = RowProgressView.detailLine(book: book, clock: clock)
        }, onChange: { fired = true })
        clock.update(bookTime: 10, currentChapter: 0)

        XCTAssertTrue(fired)
    }

    /// A chaptered row shows the chapter, so it reads only `currentChapter` and a tick inside the
    /// same chapter costs it nothing.
    func test_loadedChapteredRowProgress_ignoresTicksWithinAChapter() {
        let clock = PlaybackClock()
        let book = ViewModelSupport.chaptered()
        var fired = false

        withObservationTracking({
            _ = RowProgressView.detailLine(book: book, clock: clock)
        }, onChange: { fired = true })
        clock.update(bookTime: 10, currentChapter: 0)
        clock.update(bookTime: 20, currentChapter: 0)

        XCTAssertFalse(fired)
        XCTAssertEqual(RowProgressView.detailLine(book: book, clock: clock), "Artist · Ch 1/3")
    }

    /// The #116 lesson: a row created while its book is already loaded shows it playing, with no
    /// play event to catch, because it reads the shared state.
    func test_rowCreatedWhileItsBookIsLoaded_showsPlaying() {
        let playback = PlaybackState()
        let book = ViewModelSupport.chaptered()
        playback.setLoadedBook(book)
        playback.setIsPlaying(true)

        let detail = MediaView.DetailModel(book: book, state: playback, entry: nil)

        XCTAssertTrue(detail.isLoaded)
        XCTAssertTrue(detail.isPlaying)
    }

    func test_rowOfAnotherBook_isNeitherLoadedNorPlaying() {
        let playback = PlaybackState()
        playback.setLoadedBook(AudioModel(title: "Other", url: otherURL))
        playback.setIsPlaying(true)

        let detail = MediaView.DetailModel(book: ViewModelSupport.chaptered(), state: playback, entry: nil)

        XCTAssertFalse(detail.isLoaded)
        XCTAssertFalse(detail.isPlaying)
    }

    func test_detailLine_chapteredBook_showsAuthorAndOneBasedChapter() {
        let book = ViewModelSupport.chaptered(currentTime: 150)
        let detail = MediaView.DetailModel(book: book, state: PlaybackState(), entry: nil)

        XCTAssertEqual(detail.detailLine, "Artist · Ch 2/3")
    }

    func test_detailLine_plainBook_showsAuthorAndTimeLeft() {
        let book = plainBook(duration: 200, currentTime: 0)
        let detail = MediaView.DetailModel(book: book, state: PlaybackState(), entry: nil)

        XCTAssertTrue(detail.detailLine.hasPrefix("Artist · "), detail.detailLine)
        XCTAssertTrue(detail.detailLine.contains("left"), detail.detailLine)
        XCTAssertTrue(detail.detailLine.contains("3"), "200 s is 3 min 20 s: \(detail.detailLine)")
    }

    func test_detailLine_withoutAuthor_omitsTheSeparator() {
        var book = ViewModelSupport.chaptered()
        book.artist = ""

        XCTAssertEqual(MediaView.DetailModel(book: book, state: PlaybackState(), entry: nil).detailLine, "Ch 1/3")
    }

    func test_downloadState_followsTheBooksEntry() {
        let manager = MockBookDownloadManager()
        let store = DownloadStateStore(downloads: manager)
        let running = state([.downloaded, .downloading(fraction: 0.5), .waiting])
        manager.statesSubject.send(["42": running])

        let detail = MediaView.DetailModel(book: libriVoxBook(), state: PlaybackState(), entry: store.entry(for: "42"))

        XCTAssertEqual(detail.downloadState, running)
    }

    func test_downloadState_nilWithoutAnEntry() {
        let detail = MediaView.DetailModel(book: ViewModelSupport.chaptered(), state: PlaybackState(), entry: nil)

        XCTAssertNil(detail.downloadState)
    }
}
