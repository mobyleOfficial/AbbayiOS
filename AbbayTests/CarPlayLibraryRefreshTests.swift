//
//  CarPlayLibraryRefreshTests.swift
//  AbbayTests
//

@testable import Abbay
import CarPlay
import Combine
import XCTest

/// #95: the CarPlay library was built once at connect, so a book imported or deleted on the phone
/// never showed up (or never went away) until a reconnect, and an empty library was a blank list.
final class CarPlayLibraryRefreshTests: XCTestCase {
    private var player = MockPlayer()
    private var loadAudio = MockLoadAudioUseCase()
    private var loadAll = MockLoadAllAudiosUseCase()
    private var observer = MockPlayerObserver()
    private var libraryChanges = PassthroughSubject<Void, Never>()
    private var positionSaves = PassthroughSubject<URL, Never>()

    override func setUpWithError() throws {
        try super.setUpWithError()
        player = MockPlayer()
        loadAudio = MockLoadAudioUseCase()
        loadAll = MockLoadAllAudiosUseCase()
        observer = MockPlayerObserver()
        observer.player = player
        libraryChanges = PassthroughSubject<Void, Never>()
        positionSaves = PassthroughSubject<URL, Never>()
        DependencyContainer.configure(
            with: MockDependencyContainer(player: player, loadAudio: loadAudio, loadAllAudios: loadAll)
        )
    }

    override func tearDownWithError() throws {
        DependencyContainer.reset()
        try super.tearDownWithError()
    }

    private func makeDelegate() -> CarPlaySceneDelegate {
        let delegate = CarPlaySceneDelegate()
        delegate.loadAllAudiosUseCase = loadAll
        delegate.loadAudioUseCase = loadAudio
        delegate.playerObserver = observer
        delegate.libraryChanges = libraryChanges.eraseToAnyPublisher()
        delegate.positionSaves = positionSaves.eraseToAnyPublisher()
        return delegate
    }

    private func book(
        title: String = "Book",
        duration: Double = 400,
        currentTime: Double = 0,
        url: String = "file:///carplay/book.m4b"
    ) -> AudioModel {
        AudioModel(
            title: title,
            albumName: "Album",
            duration: duration,
            currentTime: currentTime,
            url: URL(string: url)
        )
    }

    private func items(of template: CPListTemplate) -> [CPListItem] {
        template.sections.flatMap { $0.items }.compactMap { $0 as? CPListItem }
    }

    // MARK: - Library changes

    func test_libraryChange_updatesTheShownList() {
        loadAll.stub = [book(title: "One", url: "file:///1.m4b")]
        let delegate = makeDelegate()
        let template = delegate.buildLibraryTemplate()
        delegate.setupObservers()

        loadAll.stub = [book(title: "One", url: "file:///1.m4b"), book(title: "Imported", url: "file:///2.m4b")]
        libraryChanges.send()

        XCTAssertEqual(items(of: template).map(\.text), ["One", "Imported"])
        XCTAssertEqual(delegate.audioItems.count, 2)
    }

    func test_libraryChange_dropsADeletedBook() {
        loadAll.stub = [book(title: "One", url: "file:///1.m4b"), book(title: "Two", url: "file:///2.m4b")]
        let delegate = makeDelegate()
        let template = delegate.buildLibraryTemplate()
        delegate.setupObservers()

        loadAll.stub = [book(title: "Two", url: "file:///2.m4b")]
        libraryChanges.send()

        XCTAssertEqual(items(of: template).map(\.text), ["Two"])
    }

    /// The rebuilt rows are new objects: live progress has to follow the playing book onto its
    /// new row rather than keep writing to one that is no longer shown.
    func test_libraryChange_progressFollowsThePlayingBookOntoItsNewRow() {
        let playing = book(title: "Playing", duration: 400, url: "file:///playing.m4b")
        loadAll.stub = [playing]
        player.url = playing.url
        let delegate = makeDelegate()
        let template = delegate.buildLibraryTemplate()
        delegate.setupObservers()
        observer.emitPlayUrl(playing)

        loadAll.stub = [book(title: "Imported", url: "file:///new.m4b"), playing]
        libraryChanges.send()
        observer.emitTime(100)

        let rows = items(of: template)
        XCTAssertTrue(delegate.currentPlayingItem === rows[1])
        XCTAssertEqual(rows[1].playbackProgress, 0.25, accuracy: 0.001)
    }

    func test_libraryChange_beforeTheTemplateIsBuilt_isIgnored() {
        let delegate = makeDelegate()
        delegate.setupObservers()

        libraryChanges.send()

        XCTAssertEqual(loadAll.executeCallCount, 0, "nothing is connected, so nothing to rebuild")
    }

    func test_libraryChange_afterDisconnect_isIgnored() {
        loadAll.stub = [book(title: "One", url: "file:///1.m4b")]
        let delegate = makeDelegate()
        _ = delegate.buildLibraryTemplate()
        delegate.setupObservers()
        delegate.tearDownConnection()
        let callsAtDisconnect = loadAll.executeCallCount

        libraryChanges.send()

        XCTAssertEqual(loadAll.executeCallCount, callsAtDisconnect)
        XCTAssertNil(delegate.libraryTemplate)
    }

    /// The default must be the real library signal, not a publisher nobody sends on.
    func test_defaultLibraryChanges_followsTheSnapshotWriter() {
        loadAll.stub = [book(title: "One", url: "file:///1.m4b")]
        let delegate = CarPlaySceneDelegate()
        delegate.loadAllAudiosUseCase = loadAll
        delegate.loadAudioUseCase = loadAudio
        delegate.playerObserver = observer
        let template = delegate.buildLibraryTemplate()
        delegate.setupObservers()

        loadAll.stub = [book(title: "One", url: "file:///1.m4b"), book(title: "Two", url: "file:///2.m4b")]
        NotificationCenter.default.post(name: .libraryDidChange, object: nil)

        // Delivered on the main queue, so let it drain.
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(items(of: template).map(\.text), ["One", "Two"])
    }

    // MARK: - Only rebuild when something visible changed (#150)

    /// A snapshot write where no row's text, detail or cover changed (the player's bookmark
    /// refresh in `Player.play`) must not rebuild the list: CarPlay redraws it on every
    /// `updateSections`.
    func test_libraryChange_withNothingVisibleChanged_keepsTheSameRows() {
        loadAll.stub = [book(title: "One", url: "file:///1.m4b"), book(title: "Two", url: "file:///2.m4b")]
        let delegate = makeDelegate()
        let template = delegate.buildLibraryTemplate()
        let before = items(of: template)
        delegate.setupObservers()

        libraryChanges.send()

        let after = items(of: template)
        XCTAssertEqual(after.count, 2)
        XCTAssertTrue(zip(before, after).allSatisfy { $0 === $1 }, "the rows were rebuilt for no visible change")
        XCTAssertEqual(loadAll.executeCallCount, 2, "the store is still re-read, to find out")
    }

    /// No rebuild, but a saved position that moved still shows on its row.
    func test_libraryChange_withOnlyProgressChanged_updatesTheRowInPlace() {
        loadAll.stub = [book(title: "One", duration: 400, currentTime: 0, url: "file:///1.m4b")]
        let delegate = makeDelegate()
        let template = delegate.buildLibraryTemplate()
        let row = items(of: template)[0]
        delegate.setupObservers()

        loadAll.stub = [book(title: "One", duration: 400, currentTime: 300, url: "file:///1.m4b")]
        libraryChanges.send()

        XCTAssertTrue(items(of: template)[0] === row)
        XCTAssertEqual(row.playbackProgress, 0.75, accuracy: 0.001)
        XCTAssertEqual(delegate.audioItems.first?.currentTime, 300)
    }

    func test_libraryChange_renamedBook_rebuilds() {
        loadAll.stub = [book(title: "Old Title", url: "file:///1.m4b")]
        let delegate = makeDelegate()
        let template = delegate.buildLibraryTemplate()
        let row = items(of: template)[0]
        delegate.setupObservers()

        loadAll.stub = [book(title: "New Title", url: "file:///1.m4b")]
        libraryChanges.send()

        XCTAssertFalse(items(of: template)[0] === row)
        XCTAssertEqual(items(of: template).map(\.text), ["New Title"])
    }

    func test_libraryChange_newCover_rebuilds() {
        loadAll.stub = [book(title: "One", url: "file:///1.m4b")]
        let delegate = makeDelegate()
        let template = delegate.buildLibraryTemplate()
        let row = items(of: template)[0]
        delegate.setupObservers()

        var withCover = book(title: "One", url: "file:///1.m4b")
        withCover.imageData = Data([1, 2, 3])
        loadAll.stub = [withCover]
        libraryChanges.send()

        XCTAssertFalse(items(of: template)[0] === row, "a new cover is a visible change")
    }

    func test_libraryChange_reorderedBooks_rebuilds() {
        let first = book(title: "One", url: "file:///1.m4b")
        let second = book(title: "Two", url: "file:///2.m4b")
        loadAll.stub = [first, second]
        let delegate = makeDelegate()
        let template = delegate.buildLibraryTemplate()
        delegate.setupObservers()

        loadAll.stub = [second, first]
        libraryChanges.send()

        XCTAssertEqual(items(of: template).map(\.text), ["Two", "One"])
    }

    /// The playing book's row follows the player, not the store: an in-place refresh must not
    /// pull it back to the last saved position between ticks.
    func test_libraryChange_withNothingVisibleChanged_leavesTheLiveRowToThePlayer() {
        let playing = book(title: "Playing", duration: 400, currentTime: 0, url: "file:///playing.m4b")
        loadAll.stub = [playing]
        player.url = playing.url
        let delegate = makeDelegate()
        let template = delegate.buildLibraryTemplate()
        delegate.setupObservers()
        observer.emitPlayUrl(playing)
        observer.emitTime(300)

        libraryChanges.send()

        XCTAssertEqual(items(of: template)[0].playbackProgress, 0.75, accuracy: 0.001)
    }

    // MARK: - Saved positions reach the rows (#150)

    /// The player saves every 10 s while playing (#133) and on pause or a book switch. Those
    /// saves are not library changes, so before #150 they never reached CarPlay.
    func test_positionSave_updatesThatBooksRow_withoutRebuilding() throws {
        let other = book(title: "Other", duration: 400, currentTime: 0, url: "file:///other.m4b")
        loadAll.stub = [other]
        let delegate = makeDelegate()
        let template = delegate.buildLibraryTemplate()
        let row = items(of: template)[0]
        delegate.setupObservers()
        loadAudio.stubs["file:///other.m4b"] = book(title: "Other", duration: 400, currentTime: 200, url: "file:///other.m4b")

        let libraryReads = loadAll.executeCallCount

        positionSaves.send(try XCTUnwrap(other.url))

        XCTAssertTrue(items(of: template)[0] === row)
        XCTAssertEqual(row.playbackProgress, 0.5, accuracy: 0.001)
        XCTAssertEqual(loadAll.executeCallCount, libraryReads, "a position save reads one book, not the library")
    }

    /// Switching from A to B saves A's position as it goes. A's row is handed back its stored
    /// position before that save lands, so the save has to correct it.
    func test_switchingBooks_theOldBooksSave_showsOnItsRow() throws {
        let bookA = book(title: "A", duration: 400, currentTime: 0, url: "file:///a.m4b")
        let bookB = book(title: "B", duration: 100, url: "file:///b.m4b")
        loadAll.stub = [bookA, bookB]
        player.url = bookA.url
        let delegate = makeDelegate()
        let rows = items(of: delegate.buildLibraryTemplate())
        delegate.setupObservers()
        observer.emitPlayUrl(bookA)
        observer.emitTime(300)

        observer.emitPlayUrl(bookB)
        loadAudio.stubs["file:///a.m4b"] = book(title: "A", duration: 400, currentTime: 300, url: "file:///a.m4b")
        positionSaves.send(try XCTUnwrap(bookA.url))

        XCTAssertEqual(rows[0].playbackProgress, 0.75, accuracy: 0.001, "A's row shows where A was left")
    }

    /// The playing book's own saves keep the stored copy current, so its row falls back to the
    /// right place when another book takes over, but they don't fight the live progress.
    func test_positionSave_ofThePlayingBook_updatesItsStoredPositionOnly() throws {
        let bookA = book(title: "A", duration: 400, currentTime: 0, url: "file:///a.m4b")
        let bookB = book(title: "B", duration: 100, url: "file:///b.m4b")
        loadAll.stub = [bookA, bookB]
        player.url = bookA.url
        let delegate = makeDelegate()
        let rows = items(of: delegate.buildLibraryTemplate())
        delegate.setupObservers()
        observer.emitPlayUrl(bookA)
        observer.emitTime(300)
        loadAudio.stubs["file:///a.m4b"] = book(title: "A", duration: 400, currentTime: 280, url: "file:///a.m4b")

        positionSaves.send(try XCTUnwrap(bookA.url))
        XCTAssertEqual(rows[0].playbackProgress, 0.75, accuracy: 0.001, "the live row is the player's")

        observer.emitPlayUrl(bookB)
        XCTAssertEqual(rows[0].playbackProgress, 0.7, accuracy: 0.001, "falls back to the latest save, 280/400")
    }

    func test_positionSave_ofABookNotListed_isIgnored() throws {
        loadAll.stub = [book(title: "One", url: "file:///1.m4b")]
        let delegate = makeDelegate()
        _ = delegate.buildLibraryTemplate()
        delegate.setupObservers()

        positionSaves.send(try XCTUnwrap(URL(string: "file:///elsewhere.m4b")))

        XCTAssertTrue(loadAudio.executeCalls.isEmpty, "no row to update, so nothing to read")
    }

    func test_positionSave_beforeTheTemplateIsBuilt_isIgnored() throws {
        let delegate = makeDelegate()
        delegate.setupObservers()

        positionSaves.send(try XCTUnwrap(URL(string: "file:///1.m4b")))

        XCTAssertTrue(loadAudio.executeCalls.isEmpty)
    }

    func test_positionSave_afterDisconnect_isIgnored() throws {
        loadAll.stub = [book(title: "One", url: "file:///1.m4b")]
        let delegate = makeDelegate()
        _ = delegate.buildLibraryTemplate()
        delegate.setupObservers()
        delegate.tearDownConnection()

        positionSaves.send(try XCTUnwrap(URL(string: "file:///1.m4b")))

        XCTAssertTrue(loadAudio.executeCalls.isEmpty)
    }

    /// The default must be the save use case's real signal.
    func test_defaultPositionSaves_followTheSaveNotification() throws {
        let url = try XCTUnwrap(URL(string: "file:///1.m4b"))
        loadAll.stub = [book(title: "One", duration: 400, currentTime: 0, url: url.absoluteString)]
        loadAudio.stubs[url.absoluteString] = book(
            title: "One",
            duration: 400,
            currentTime: 100,
            url: url.absoluteString
        )
        let delegate = CarPlaySceneDelegate()
        delegate.loadAllAudiosUseCase = loadAll
        delegate.loadAudioUseCase = loadAudio
        delegate.playerObserver = observer
        delegate.libraryChanges = libraryChanges.eraseToAnyPublisher()
        let template = delegate.buildLibraryTemplate()
        delegate.setupObservers()

        NotificationCenter.default.post(
            name: .playbackPositionDidSave,
            object: nil,
            userInfo: [PlaybackPositionSave.urlKey: url]
        )

        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(items(of: template)[0].playbackProgress, 0.25, accuracy: 0.001)
    }

    // MARK: - Empty state

    func test_buildLibraryTemplate_explainsAnEmptyLibrary() {
        let delegate = makeDelegate()

        let template = delegate.buildLibraryTemplate()

        XCTAssertEqual(template.emptyViewTitleVariants, [Localizable.carPlayEmptyLibraryTitle.localized])
        XCTAssertEqual(template.emptyViewSubtitleVariants, [Localizable.carPlayEmptyLibrarySubtitle.localized])
    }

    func test_libraryChange_toEmpty_showsNoRows() {
        loadAll.stub = [book(title: "Last One", url: "file:///1.m4b")]
        let delegate = makeDelegate()
        let template = delegate.buildLibraryTemplate()
        delegate.setupObservers()

        loadAll.stub = []
        libraryChanges.send()

        XCTAssertTrue(items(of: template).isEmpty, "an empty list is what lets the empty view show")
        XCTAssertFalse(template.emptyViewTitleVariants.isEmpty)
    }
}
