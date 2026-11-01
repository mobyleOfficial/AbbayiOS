//
//  RenameBookTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// #322: a book without a title is called by its file's name, and an imported book can be renamed,
/// the new name reaching its row (and Siri's snapshot), the player and the screens.
@MainActor
final class RenameBookTests: XCTestCase {
    private let bookURL = URL(fileURLWithPath: "/rename-\(UUID().uuidString)/hunger-games-joined.mp3")

    override func tearDown() async throws {
        DeleteAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(AudioModel(url: bookURL))
        NowPlayingManager.shared.clearNowPlaying()
        try await super.tearDown()
    }

    // MARK: - The file's name

    func test_fileTitle_isTheFilesNameWithoutItsExtension() {
        XCTAssertEqual(AudioModel.fileTitle(for: bookURL), "hunger-games-joined")
        XCTAssertEqual(AudioModel.fileTitle(for: URL(string: "librivox://emma_librivox")), "", "not a file")
        XCTAssertEqual(AudioModel.title("  The Hunger Games ", orFileTitleOf: bookURL), "The Hunger Games")
        XCTAssertEqual(AudioModel.title("   ", orFileTitleOf: bookURL), "hunger-games-joined")
        XCTAssertEqual(AudioModel.title(nil, orFileTitleOf: bookURL), "hunger-games-joined")
    }

    /// A book saved without a title (an MP3 with no metadata, imported before #322) loads with its
    /// file's name.
    func test_aSavedBookWithoutATitle_loadsWithItsFilesName() throws {
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter())
            .execute(AudioModel(title: "", duration: 100, url: bookURL))

        XCTAssertEqual(LoadAudioUseCase().execute(url: bookURL)?.title, "hunger-games-joined")
    }

    // MARK: - Renaming

    func test_rename_savesTheName_andAnEmptyOneGivesBackTheFilesName() throws {
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter())
            .execute(AudioModel(title: "", duration: 100, url: bookURL))
        let snapshot = MockLibrarySnapshotWriter()
        let sut = RenameAudioUseCase(snapshotWriter: snapshot)

        XCTAssertEqual(sut.execute(title: " The Hunger Games ", bookURL: bookURL), "The Hunger Games")
        XCTAssertEqual(LoadAudioUseCase().execute(url: bookURL)?.title, "The Hunger Games")
        XCTAssertEqual(snapshot.refreshCallCount, 1, "Siri's snapshot is rewritten")

        XCTAssertEqual(sut.execute(title: "", bookURL: bookURL), "hunger-games-joined")
        XCTAssertEqual(LoadAudioUseCase().execute(url: bookURL)?.title, "hunger-games-joined")
    }

    func test_rename_noSuchBook_writesNothing() {
        let snapshot = MockLibrarySnapshotWriter()

        XCTAssertNil(RenameAudioUseCase(snapshotWriter: snapshot).execute(title: "Name", bookURL: bookURL))
        XCTAssertEqual(snapshot.refreshCallCount, 0)
    }

    func test_renamer_handsTheTitleToTheLoadedBook_andTellsTheScreens() throws {
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter())
            .execute(AudioModel(title: "", duration: 100, url: bookURL))
        let player = CountingMockPlayer()
        let center = PlaybackCenter(player: player)
        let book = AudioModel(title: "hunger-games-joined", duration: 100, url: bookURL)
        player.emitPlayUrl(book)
        let notifications = NotificationCenter()
        var posted: String?
        let observer = notifications.addObserver(forName: .bookTitleDidChange, object: bookURL, queue: nil) {
            posted = $0.userInfo?[BookRenamer.titleKey] as? String
        }
        defer { notifications.removeObserver(observer) }

        BookRenamer(
            rename: RenameAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()),
            playback: center,
            notificationCenter: notifications
        ).rename(book, to: "The Hunger Games")

        XCTAssertEqual(center.state.loadedBook?.title, "The Hunger Games")
        XCTAssertEqual(player.replacedTitles.last?.title, "The Hunger Games")
        XCTAssertEqual(posted, "The Hunger Games")
    }

    func test_aLibriVoxBook_isNotRenamed() {
        var book = AudioModel(title: "Emma", url: URL(string: "librivox://emma_librivox"))
        book.librivoxID = "emma_librivox"

        XCTAssertFalse(BookRenamer.canRename(book))
        XCTAssertTrue(BookRenamer.canRename(AudioModel(title: "", url: bookURL)))
    }

    func test_player_replaceTitle_reachesNowPlaying() {
        let player = Player(
            savePlaybackPositionUseCase: MockSavePlaybackPositionUseCase(),
            intentDonor: MockIntentDonor(),
            librarySnapshotWriter: MockLibrarySnapshotWriter(),
            audioSessionActivator: MockAudioSessionActivator(),
            bookmarkProvider: MockBookmarkProvider(),
            lastPlayed: .inMemory(),
            launchState: .inMemory()
        )
        var book = AudioModel(title: "hunger-games-joined", duration: 100, url: bookURL)
        player.play(&book)

        player.replaceTitle("The Hunger Games", ofBookAt: bookURL)

        XCTAssertEqual(NowPlayingManager.shared.currentAudio?.title, "The Hunger Games")
    }

    func test_screens_takeTheNewTitle_ofTheirBookOnly() {
        let presentation = PlayerPresentation()
        presentation.open(AudioModel(title: "old", url: bookURL), animated: false)
        let screen = PlayerViewModel(
            AudioModel(title: "old", url: bookURL), state: PlaybackState(), player: nil, downloads: nil
        )

        presentation.titleChanged("Other", ofBookAt: URL(fileURLWithPath: "/another.mp3"))
        screen.presentedTitleChanged("Other", ofBookAt: URL(fileURLWithPath: "/another.mp3"))
        XCTAssertEqual(presentation.presentedBook?.title, "old")
        XCTAssertEqual(screen.book.title, "old")

        presentation.titleChanged("New", ofBookAt: bookURL)
        screen.presentedTitleChanged("New", ofBookAt: bookURL)
        XCTAssertEqual(presentation.presentedBook?.title, "New")
        XCTAssertEqual(screen.book.title, "New")
    }
}
