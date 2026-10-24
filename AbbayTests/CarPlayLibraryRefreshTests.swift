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

    override func setUpWithError() throws {
        try super.setUpWithError()
        player = MockPlayer()
        loadAudio = MockLoadAudioUseCase()
        loadAll = MockLoadAllAudiosUseCase()
        observer = MockPlayerObserver()
        observer.player = player
        libraryChanges = PassthroughSubject<Void, Never>()
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
