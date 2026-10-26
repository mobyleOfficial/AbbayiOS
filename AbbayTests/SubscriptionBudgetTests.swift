//
//  SubscriptionBudgetTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// The owner's subscription budget, app-wide: the player's publishers are subscribed exactly three
/// times (play URL, time, playing status — all by `PlaybackCenter`) and the download manager's
/// `statesPublisher` once (by `DownloadStateStore`), however many rows exist, however often the
/// details screen opens and closes, and however many ticks arrive. Any view model that still
/// subscribes on its own breaks it.
@MainActor
final class SubscriptionBudgetTests: XCTestCase {
    func test_appWide_playerSubscriptions_stayAtThree() {
        let player = CountingMockPlayer()
        let downloads = CountingMockBookDownloadManager()
        let center = PlaybackCenter(player: player, loadAudio: MockLoadAudioUseCase())
        let store = DownloadStateStore(downloads: downloads)
        let books = (0..<25).map(Self.book)

        // Everything the screens build: the library, 25 rows, the bar's presentation, the details
        // screen's models and a LibriVox details page.
        let library = MediaListViewModel(
            playback: center,
            loadAllAudiosUseCase: MockLoadAllAudiosUseCase(),
            deleteAudioUseCase: MockDeleteAudioUseCase(),
            fileLoader: MockFileLoader(),
            loadAudioUseCase: MockLoadAudioUseCase()
        )
        let rows = books.map { MediaViewModel($0, player: center.player, downloads: store) }
        let presentation = PlayerPresentation(playback: center.state)
        let libriVoxDetails = Self.libriVoxDetails(downloads: downloads, store: store)
        books.forEach { _ = store.entry(for: $0.librivoxID ?? "") }

        rows[3].play()
        player.emitPlayUrl(books[3])
        player.emitPlaying(true)
        let details = Self.openAndClose(
            times: 3,
            book: books[3],
            presentation: presentation,
            center: center,
            store: store
        )
        for tick in 1...30 {
            player.emitTime(Double(tick))
            _ = details.bookTime(in: center.clock)
            _ = MiniPlayerActions.progress(book: books[3], chapter: center.clock.currentChapter, bookTime: Double(tick))
        }
        let waiting = BookDownloadState(chapters: [.waiting], isPaused: false, fraction: 0)
        downloads.mock.statesSubject.send(["budget_1": waiting])
        rows[1].toggleDownload()
        rows[3].pause()
        player.emitPlaying(false)
        library.loadedBookChanged(to: books[3])

        XCTAssertEqual(player.urlSubscriptionCount, 1)
        XCTAssertEqual(player.timeSubscriptionCount, 1)
        XCTAssertEqual(player.playingSubscriptionCount, 1)
        XCTAssertEqual(
            player.urlSubscriptionCount + player.timeSubscriptionCount + player.playingSubscriptionCount,
            3,
            "player subscriptions"
        )
        XCTAssertEqual(downloads.subscriptionCount, 1, "statesPublisher subscriptions")
        withExtendedLifetime((library, rows, libriVoxDetails)) {}
    }

    // MARK: - Helpers

    private static func book(_ index: Int) -> AudioModel {
        var book = AudioModel(title: "Book \(index)", duration: 400, url: URL(string: "file:///budget/\(index).m4b"))
        book.librivoxID = "budget_\(index)"
        return book
    }

    private static func libriVoxDetails(
        downloads: BookDownloadManagerProtocol,
        store: DownloadStateStore
    ) -> LibriVoxDetailViewModel {
        LibriVoxDetailViewModel(
            book: LibriVoxBook(
                id: "budget_0",
                title: "Book 0",
                authors: "",
                descriptionText: "",
                language: "English",
                totalSeconds: 400,
                coverURL: URL(fileURLWithPath: "/cover"),
                sections: []
            ),
            client: MockLibriVoxClient(),
            downloads: downloads,
            downloadStates: store,
            saveAudio: MockSaveAudioUseCase(),
            path: FakeNetworkPath(),
            loadAudio: MockLoadAudioUseCase(),
            onAdded: { _ in },
            openPlayer: { _ in }
        )
    }

    /// Opens and closes the details screen like the overlay does: one fresh model per presentation,
    /// read the way the screen reads it. Returns the last one.
    private static func openAndClose(
        times: Int,
        book: AudioModel,
        presentation: PlayerPresentation,
        center: PlaybackCenter,
        store: DownloadStateStore
    ) -> PlayerViewModel {
        let models = PlayerDetailsModels()
        var model: PlayerViewModel?
        for _ in 0..<times {
            presentation.open(book, animated: false)
            let current = models.model(
                for: book,
                presentationID: presentation.presentationID,
                state: center.state,
                player: center.player,
                downloads: store
            )
            _ = current.book
            _ = current.isPlaying
            _ = current.downloadEntry
            model = current
            presentation.close(animated: false)
        }
        return model ?? PlayerViewModel(book, state: center.state, player: center.player, downloads: store)
    }
}
