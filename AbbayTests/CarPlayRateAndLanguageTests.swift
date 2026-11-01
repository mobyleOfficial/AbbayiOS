//
//  CarPlayRateAndLanguageTests.swift
//  AbbayTests
//

@testable import Abbay
import CarPlay
import Combine
import XCTest

/// CarPlay's Now Playing rate button (#150) and its strings following the in-app language
/// (#152). Same injection seam as `CarPlaySceneDelegateTests`: `didConnect` can't be driven from a
/// test, so the handlers it wires are called directly.
final class CarPlayRateAndLanguageTests: XCTestCase {
    private var player = MockPlayer()
    private var loadAudio = MockLoadAudioUseCase()
    private var loadAll = MockLoadAllAudiosUseCase()
    private var observer = MockPlayerObserver()
    private var libraryChanges = PassthroughSubject<Void, Never>()
    private var languageChanges = PassthroughSubject<Void, Never>()

    override func setUpWithError() throws {
        try super.setUpWithError()
        player = MockPlayer()
        loadAudio = MockLoadAudioUseCase()
        loadAll = MockLoadAllAudiosUseCase()
        observer = MockPlayerObserver()
        observer.player = player
        libraryChanges = PassthroughSubject<Void, Never>()
        languageChanges = PassthroughSubject<Void, Never>()
        AbbayBundle.languageCode = nil
        DependencyContainer.configure(
            with: MockDependencyContainer(player: player, loadAudio: loadAudio, loadAllAudios: loadAll)
        )
    }

    override func tearDownWithError() throws {
        AbbayBundle.languageCode = nil
        CPNowPlayingTemplate.shared.upNextTitle = Localizable.chapterSelectionTitle.localized
        DependencyContainer.reset()
        try super.tearDownWithError()
    }

    private func makeDelegate() -> CarPlaySceneDelegate {
        let delegate = CarPlaySceneDelegate()
        delegate.loadAllAudiosUseCase = loadAll
        delegate.loadAudioUseCase = loadAudio
        delegate.playerObserver = observer
        delegate.libraryChanges = libraryChanges.eraseToAnyPublisher()
        delegate.languageChanges = languageChanges.eraseToAnyPublisher()
        return delegate
    }

    // MARK: - Playback rate button (#150)

    /// The Now Playing template's rate button shows the rate from Now Playing info, and each
    /// tap moves the loaded book to the next preset, saved as that book's speed (#140).
    func test_rateButtonTap_movesTheLoadedBookToTheNextPreset() {
        player.url = URL(string: "file:///carplay/book.m4b")
        player.playbackRate = 1
        let delegate = makeDelegate()

        delegate.rateButtonTapped()

        XCTAssertEqual(player.rateCalls, [1.2])
    }

    func test_rateButtonTaps_cycleThroughThePresets() {
        player.url = URL(string: "file:///carplay/book.m4b")
        player.playbackRate = 2
        let delegate = makeDelegate()

        delegate.rateButtonTapped()
        delegate.rateButtonTapped()

        XCTAssertEqual(player.rateCalls, [2.5, 0.8], "after the fastest preset it wraps to the slowest")
    }

    func test_rateButtonTap_withNothingLoaded_doesNothing() {
        let delegate = makeDelegate()

        delegate.rateButtonTapped()

        XCTAssertTrue(player.rateCalls.isEmpty, "there is no book to give the speed to")
    }

    func test_nowPlayingButtons_areTheRateButtonThenStartOver() {
        let delegate = makeDelegate()

        let buttons = delegate.makeNowPlayingButtons()

        XCTAssertEqual(buttons.count, 2)
        XCTAssertTrue(buttons.first is CPNowPlayingPlaybackRateButton)
        XCTAssertTrue(buttons.last is CPNowPlayingImageButton, "↺ Start over (#299)")
    }

    // MARK: - Start over (#299)

    /// ↺ plays the chapter playing from its start, whatever was saved for it.
    func test_startOver_playsTheCurrentChapterFromItsStart() {
        let book = ViewModelSupport.chaptered(currentTime: 150)
        player.url = book.url
        player.currentTime = 150

        XCTAssertTrue(CarPlaySceneDelegate.startOver(player: player, book: book))

        XCTAssertEqual(player.seekSeconds, [100], "chapter two's start")
        XCTAssertEqual(player.playChapterCalls, [1], "and plays it")
    }

    func test_startOver_anotherBookOrNoChapters_doesNothing() {
        var book = ViewModelSupport.chaptered()
        player.url = URL(string: "file:///carplay/other.m4b")
        XCTAssertFalse(CarPlaySceneDelegate.startOver(player: player, book: book), "not the loaded book")

        book.chapters = []
        player.url = book.url
        XCTAssertFalse(CarPlaySceneDelegate.startOver(player: player, book: book), "no chapter to start over")
        XCTAssertEqual(player.seekSeconds, [])
        XCTAssertEqual(player.playChapterCalls, [])
    }

    // MARK: - In-app language (#152)

    /// CarPlay's own strings come from `Localizable`, so they follow the in-app language. A change
    /// made on the phone while connected reaches the strings that can change in place.
    func test_languageChange_whileConnected_updatesTheTemplatesStrings() {
        AbbayBundle.languageCode = "en"
        defer { AbbayBundle.languageCode = nil }
        let delegate = makeDelegate()
        let template = delegate.buildLibraryTemplate()
        delegate.setupObservers()

        AbbayBundle.languageCode = "pt-BR"
        languageChanges.send()

        XCTAssertEqual(template.emptyViewTitleVariants, ["Nenhum audiolivro ainda"])
        XCTAssertEqual(template.emptyViewSubtitleVariants, [Localizable.carPlayEmptyLibrarySubtitle.localized])
        XCTAssertEqual(CPNowPlayingTemplate.shared.upNextTitle, "Seleção de capítulos")
    }

    /// `CPListTemplate.title` is read-only, so the library's title needs a new root template, which
    /// waits until the library is on top rather than pull the driver out of Now Playing.
    func test_languageChange_marksTheLibraryTitleStale() {
        let delegate = makeDelegate()
        _ = delegate.buildLibraryTemplate()
        delegate.setupObservers()

        languageChanges.send()

        XCTAssertTrue(delegate.isLibraryTitleStale)
    }

    func test_buildingTheLibrary_clearsAStaleTitle() {
        let delegate = makeDelegate()
        _ = delegate.buildLibraryTemplate()
        delegate.setupObservers()
        languageChanges.send()

        _ = delegate.buildLibraryTemplate()

        XCTAssertFalse(delegate.isLibraryTitleStale)
    }

    func test_libraryTitle_isReplacedOnlyWhileTheLibraryIsOnTop() {
        let library = CPListTemplate(title: "Library", sections: [])
        let chapters = CPListTemplate(title: "Chapters", sections: [])

        XCTAssertTrue(CarPlaySceneDelegate.canReplaceLibrary(top: library, library: library))
        XCTAssertFalse(CarPlaySceneDelegate.canReplaceLibrary(top: CPNowPlayingTemplate.shared, library: library))
        XCTAssertFalse(CarPlaySceneDelegate.canReplaceLibrary(top: chapters, library: library))
        XCTAssertFalse(CarPlaySceneDelegate.canReplaceLibrary(top: nil, library: library))
    }

    func test_languageChange_beforeConnecting_isIgnored() {
        let delegate = makeDelegate()
        delegate.setupObservers()

        languageChanges.send()

        XCTAssertFalse(delegate.isLibraryTitleStale, "nothing is shown yet")
    }

    /// The default must be the settings' real signal.
    func test_choosingALanguage_postsTheChange() {
        let changed = expectation(forNotification: .appLanguageDidChange, object: nil)

        LiveSettingsEffects().apply(language: .english)

        wait(for: [changed], timeout: 1)
        AbbayBundle.languageCode = nil
    }
}
