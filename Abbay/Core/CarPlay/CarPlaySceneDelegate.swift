//
//  CarPlaySceneDelegate.swift
//  Abbay
//

import CarPlay
import Combine
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    // MARK: - Properties

    private var interfaceController: CPInterfaceController?

    // MARK: - Injection seams
    //
    // UIKit instantiates this type itself (`config.delegateClass = CarPlaySceneDelegate.self`),
    // so there is no initialiser to inject through -- settable properties are the only option,
    // the same approach `AppDelegate` takes.
    //
    // `lazy var` rather than `let` for the same reason it is lazy in `AppDelegate`: these
    // defaults reach `DependencyContainer.shared`, which traps when unconfigured, and
    // `LoadAllAudiosUseCase` touches Core Data. Resolving them at property-initialisation time
    // would run before `configure()` on any future change to scene-connection ordering.
    //
    // Resolved from `DependencyContainer` rather than constructed directly, so CarPlay shares
    // the one player and the one set of use cases with the rest of the app.
    lazy var loadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol = DependencyContainer.shared.loadAllAudios
    lazy var loadAudioUseCase: LoadAudioUseCaseProtocol = DependencyContainer.shared.loadAudio
    // The one remaining `PlayerObserver` consumer: the rest of the app reads `PlaybackCenter`.
    lazy var playerObserver: PlayerObserverProtocol = PlayerObserver(DependencyContainer.shared.player)
    /// The app's one throttled Siri refresher, shared with the phone's foreground hook (#160).
    lazy var siriContext: SiriContextRefreshing = DependencyContainer.shared.siriContext
    /// Fires when the library changes on the phone (import, delete, LibriVox addition), so the
    /// list can be rebuilt while connected (#95). Delivered on main: writes can come from any
    /// thread, and templates must only be touched from main.
    var libraryChanges: AnyPublisher<Void, Never> = NotificationCenter.default
        .publisher(for: .libraryDidChange)
        .map { _ in () }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    /// The URL of each book whose position was just saved (every 10 s while playing, and on pause
    /// or a book switch), so that row's progress follows while connected (#150). On main.
    var positionSaves: AnyPublisher<URL, Never> = NotificationCenter.default
        .publisher(for: .playbackPositionDidSave)
        .compactMap { $0.userInfo?[PlaybackPositionSave.urlKey] as? URL }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    /// Fires when the in-app language changes on the phone, so CarPlay's own strings follow it
    /// while connected (#152). On main.
    var languageChanges: AnyPublisher<Void, Never> = NotificationCenter.default
        .publisher(for: .appLanguageDidChange)
        .map { _ in () }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()

    // MARK: - State
    //
    // Internal rather than private so tests can assert it. `CPInterfaceController` has no public
    // initialiser, so `didConnect` cannot be driven from a test and this state is otherwise
    // unreachable -- see #96.
    private(set) var audioItems: [AudioModel] = []
    private(set) var currentAudio: AudioModel?
    private(set) var currentPlayingItem: CPListItem?

    /// Rows keyed by book URL, so the live-progress row can be re-resolved when playback moves
    /// to a different book from outside CarPlay (#92).
    private var listItemsByURL: [URL: CPListItem] = [:]
    private(set) var currentPlayingURL: URL?

    /// The root list, kept so a library change can update it in place.
    private(set) var libraryTemplate: CPListTemplate?
    /// What each shown row draws apart from its progress, in order: a refresh that finds the same
    /// contents updates progress in place instead of rebuilding the list (#150).
    private var shownRows: [RowContent] = []
    /// The language changed while connected and the library's title (read-only on
    /// `CPListTemplate`) still shows the old one. Cleared when the library is rebuilt.
    private(set) var isLibraryTitleStale = false
    private var cancellables = Set<AnyCancellable>()

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        interfaceController.delegate = self

        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.isUpNextButtonEnabled = true
        nowPlaying.upNextTitle = Localizable.chapterSelectionTitle.localized
        nowPlaying.updateNowPlayingButtons(makeNowPlayingButtons())
        nowPlaying.add(self)

        setupObservers()

        interfaceController.setRootTemplate(buildLibraryTemplate(), animated: true, completion: nil)

        // Resolve current audio if already playing before CarPlay connected
        if let playerUrl = playerObserver.player.url {
            currentAudio = audioItems.first { $0.url == playerUrl }
        }

        carPlayBecameActive()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        carPlayBecameActive()
    }

    /// A CarPlay-only session (phone locked) never makes the window scene active, so the phone's
    /// foreground refresh misses it: ask for the same throttled refresh here (#160). Connecting and
    /// becoming active both call it; the throttle drops the second. Internal for tests, since
    /// neither callback can be driven from one.
    func carPlayBecameActive() {
        siriContext.refreshIfDue(.carPlay)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        tearDownConnection()
    }

    /// Everything `didDisconnect` does, split out because `CPInterfaceController` cannot be
    /// constructed in a test.
    func tearDownConnection() {
        CPNowPlayingTemplate.shared.remove(self)
        playerObserver.cancelTimeSubscription()
        playerObserver.cancelUrlSubscription()
        cancellables.removeAll()
        self.interfaceController = nil
        self.libraryTemplate = nil
        self.shownRows = []
        self.isLibraryTitleStale = false
        self.audioItems = []
        self.currentAudio = nil
        self.currentPlayingItem = nil
        self.currentPlayingURL = nil
        self.listItemsByURL = [:]
    }

    // MARK: - Observers

    func setupObservers() {
        playerObserver.subscribeToPlayUrlPublisher { [weak self] audio in
            guard let self else { return }
            // Order matters: both chapter-list entry points gate on `currentAudio`.
            self.currentAudio = audio
            // Progress is computed from `currentAudio`, so the row it is written to has to move
            // with it (#92).
            self.trackRow(for: audio)
            // Playback can start from Siri, the phone UI or a remote command. Without this
            // CarPlay stays on the library list while audio plays, which is indistinguishable
            // from the trigger having failed.
            self.showNowPlayingIfNeeded()
        }

        playerObserver.subscribeToTimePublisher { [weak self] time in
            guard let self, let audio = self.currentAudio, audio.duration > 0 else { return }
            let progress = CGFloat(time.seconds / audio.duration)
            self.currentPlayingItem?.playbackProgress = progress
        }

        libraryChanges
            .sink { [weak self] in self?.refreshLibrary() }
            .store(in: &cancellables)
        positionSaves
            .sink { [weak self] url in self?.refreshProgress(forURL: url) }
            .store(in: &cancellables)
        languageChanges
            .sink { [weak self] in self?.languageDidChange() }
            .store(in: &cancellables)
    }

    // MARK: - Template Builders

    func buildLibraryTemplate() -> CPListTemplate {
        let template = CPListTemplate(
            title: Localizable.libraryTitle.localized,
            sections: buildLibrarySections(from: loadAllAudiosUseCase.execute())
        )
        // Shown by CarPlay only while the list has no rows. Books can only be added on the phone,
        // so say so rather than leave a blank list (#95).
        applyEmptyViewStrings(to: template)
        libraryTemplate = template
        isLibraryTitleStale = false
        return template
    }

    private func applyEmptyViewStrings(to template: CPListTemplate) {
        template.emptyViewTitleVariants = [Localizable.carPlayEmptyLibraryTitle.localized]
        template.emptyViewSubtitleVariants = [Localizable.carPlayEmptyLibrarySubtitle.localized]
    }

    /// Re-reads the store. When no row's text, detail, cover or order changed (the player's
    /// bookmark refresh, a download flag), the rows stay and only their saved progress is
    /// updated: `updateSections` redraws the whole list (#150). No-op until the list is built.
    func refreshLibrary() {
        guard let libraryTemplate else { return }
        let audios = loadAllAudiosUseCase.execute()
        guard audios.map(RowContent.init) != shownRows else {
            audioItems = audios
            audios.forEach(showStoredProgress(of:))
            return
        }
        libraryTemplate.updateSections(buildLibrarySections(from: audios))
    }

    /// A book's position was saved: re-read that one book and show its saved progress on its row,
    /// unless it is the playing row, which the player drives. The stored copy is updated either
    /// way, so a row handed back by `trackRow` shows where its book was left (#150).
    func refreshProgress(forURL url: URL) {
        guard libraryTemplate != nil,
              let index = audioItems.firstIndex(where: { $0.url == url }),
              let stored = loadAudioUseCase.execute(url: url)
        else { return }
        audioItems[index].currentTime = stored.currentTime
        showStoredProgress(of: audioItems[index])
    }

    /// Sets a non-playing row's progress to its book's saved position, if that changed.
    private func showStoredProgress(of audio: AudioModel) {
        guard let url = audio.url, url != currentPlayingURL,
              let item = listItemsByURL[url],
              let progress = Self.progress(of: audio),
              abs(item.playbackProgress - progress) > 0.0005
        else { return }
        item.playbackProgress = progress
    }

    /// The saved position as a 0…1 ratio; nil without a duration.
    static func progress(of audio: AudioModel) -> CGFloat? {
        guard audio.duration > 0 else { return nil }
        return CGFloat(min(max(audio.currentTime / audio.duration, 0), 1))
    }

    /// Sets `audioItems` and rebuilds every row. The rows are new objects, so the
    /// live-progress row is re-resolved to the playing book's new row.
    private func buildLibrarySections(from audios: [AudioModel]) -> [CPListSection] {
        audioItems = audios
        shownRows = audios.map(RowContent.init)
        listItemsByURL = [:]
        currentPlayingItem = nil

        let listItems = audioItems.map { audio in
            buildListItem(for: audio)
        }

        if currentPlayingItem == nil {
            currentPlayingItem = currentPlayingURL.flatMap { listItemsByURL[$0] }
        }

        return [CPListSection(items: listItems)]
    }

    func buildListItem(for audio: AudioModel) -> CPListItem {
        let item = CPListItem(
            text: audio.title,
            detailText: RowContent.detailText(of: audio)
        )

        if let imageData = audio.imageData, let image = UIImage(data: imageData) {
            item.setImage(image)
        } else {
            item.setImage(UIImage(systemName: "book.closed"))
        }

        if let progress = Self.progress(of: audio) {
            item.playbackProgress = progress
        }

        if let url = audio.url {
            listItemsByURL[url] = item
            // Seed the tracked row when this book is already loaded, so progress starts flowing
            // without waiting for the next publish.
            if url == playerObserver.player.url {
                currentPlayingURL = url
                currentPlayingItem = item
            }
        }

        item.handler = { [weak self] _, completion in
            self?.handleAudioSelection(audio)
            completion()
        }

        return item
    }

    func buildChapterListTemplate(for audio: AudioModel) -> CPListTemplate {
        let player = playerObserver.player
        let currentChapterIndex = audio.currentChapter(for: player.currentTime)

        let items = audio.chapters.enumerated().map { index, chapter -> CPListItem in
            let item = CPListItem(
                text: chapter.title,
                detailText: chapter.startTime.timestamp
            )

            if index == currentChapterIndex {
                item.setImage(UIImage(systemName: "speaker.wave.2.fill"))
            } else {
                item.setImage(UIImage(systemName: "book.pages"))
            }

            item.handler = { [weak self] _, completion in
                player.seek(chapter.startTime)
                self?.interfaceController?.popTemplate(animated: true, completion: nil)
                completion()
            }

            return item
        }

        let section = CPListSection(items: items)
        return CPListTemplate(title: Localizable.chapterSelectionTitle.localized, sections: [section])
    }

    // MARK: - Playback

    /// Points the live-progress row at the book that is actually playing, and hands the row it
    /// is leaving back its own stored position so it does not sit frozen mid-animation showing a
    /// different book's progress.
    func trackRow(for audio: AudioModel) {
        let newURL = audio.url
        if let previousURL = currentPlayingURL, previousURL != newURL {
            restoreStoredProgress(forURL: previousURL)
        }
        currentPlayingURL = newURL
        currentPlayingItem = newURL.flatMap { listItemsByURL[$0] }
    }

    private func restoreStoredProgress(forURL url: URL) {
        guard let item = listItemsByURL[url],
              let model = audioItems.first(where: { $0.url == url }),
              let progress = Self.progress(of: model) else { return }
        item.playbackProgress = progress
    }

    func handleAudioSelection(_ audio: AudioModel) {
        // Fetch fresh model from CoreData to get the latest saved currentTime. A miss means the
        // book was deleted on the phone after this row was built: the listed copy's URL is dead,
        // so drop the stale row instead of handing it to the player (#95).
        guard var freshAudio = loadAudioUseCase.execute(url: audio.url) else {
            refreshLibrary()
            return
        }
        // Track before playing: replaying the already-loaded book does not publish a URL,
        // so the subscription would not fire and the row would never be claimed.
        trackRow(for: freshAudio)
        playerObserver.player.play(&freshAudio)

        showNowPlayingIfNeeded()
    }

    /// Whether the now-playing template still needs pushing, given the current stack.
    ///
    /// False once it is anywhere in the stack: pushing a template that is already present
    /// duplicates it, and when the user has the chapter list open on top of it they should
    /// not be yanked back by a track change. Pure and `static` so it is testable without a
    /// live `CPInterfaceController` (see #96 for the delegate's missing injection seam).
    static func needsNowPlayingPush(templates: [CPTemplate], nowPlaying: CPTemplate) -> Bool {
        !templates.contains { $0 === nowPlaying }
    }

    private func showNowPlayingIfNeeded() {
        guard let interfaceController else { return }
        let nowPlaying = CPNowPlayingTemplate.shared
        guard Self.needsNowPlayingPush(
            templates: interfaceController.templates,
            nowPlaying: nowPlaying
        ) else { return }
        interfaceController.pushTemplate(nowPlaying, animated: true, completion: nil)
    }
}

// MARK: - Row contents

extension CarPlaySceneDelegate {
    /// Everything a library row draws except its progress. Two refreshes with equal contents, in
    /// the same order, would draw the same list (#150).
    struct RowContent: Equatable {
        let url: URL?
        let text: String
        let detailText: String
        let imageData: Data?

        init(_ audio: AudioModel) {
            url = audio.url
            text = audio.title
            detailText = Self.detailText(of: audio)
            imageData = audio.imageData
        }

        static func detailText(of audio: AudioModel) -> String {
            audio.artist.isEmpty ? audio.albumName : audio.artist
        }
    }
}

// MARK: - Playback rate (#150)

extension CarPlaySceneDelegate {
    /// The Now Playing template's own buttons. The rate button shows the rate the app reports in
    /// Now Playing info (`NowPlayingManager`, the book's speed) and leaves the cycling to the app.
    func makeNowPlayingButtons() -> [CPNowPlayingButton] {
        [CPNowPlayingPlaybackRateButton { [weak self] _ in self?.rateButtonTapped() }]
    }

    /// Moves the loaded book to the next preset, saved as that book's speed exactly as the
    /// player's speed sheet and the lock screen's rate command do (#140).
    func rateButtonTapped() {
        let player = playerObserver.player
        guard player.url != nil else { return }
        player.setPlaybackRate(PlaybackSpeed.nextPreset(after: player.playbackRate))
    }
}

// MARK: - In-app language (#152)

extension CarPlaySceneDelegate: CPInterfaceControllerDelegate {
    /// CarPlay's strings come from `Localizable`, so a connection made after a language change
    /// already follows it. This handles a change made on the phone while connected: what can
    /// change in place does; the library's title, read-only on `CPListTemplate`, needs a new root
    /// template, which waits until the library is on top.
    func languageDidChange() {
        guard let libraryTemplate else { return }
        CPNowPlayingTemplate.shared.upNextTitle = Localizable.chapterSelectionTitle.localized
        applyEmptyViewStrings(to: libraryTemplate)
        isLibraryTitleStale = true
        replaceLibraryIfStale()
    }

    /// Whether the root can be swapped without moving the driver: only while the library itself
    /// is on top. `setRootTemplate` pops everything above it.
    static func canReplaceLibrary(top: CPTemplate?, library: CPTemplate) -> Bool {
        guard let top else { return false }
        return top === library
    }

    private func replaceLibraryIfStale() {
        guard isLibraryTitleStale,
              let interfaceController,
              let libraryTemplate,
              Self.canReplaceLibrary(top: interfaceController.topTemplate, library: libraryTemplate)
        else { return }
        interfaceController.setRootTemplate(buildLibraryTemplate(), animated: false, completion: nil)
    }

    func templateDidAppear(_ aTemplate: CPTemplate, animated: Bool) {
        guard aTemplate === libraryTemplate else { return }
        replaceLibraryIfStale()
    }
}

// MARK: - CPNowPlayingTemplateObserver

extension CarPlaySceneDelegate: CPNowPlayingTemplateObserver {
    func nowPlayingTemplateAlbumArtistButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        guard let audio = currentAudio, !audio.chapters.isEmpty else { return }
        let chapterList = buildChapterListTemplate(for: audio)
        interfaceController?.pushTemplate(chapterList, animated: true, completion: nil)
    }

    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        guard let audio = currentAudio, !audio.chapters.isEmpty else { return }
        let chapterList = buildChapterListTemplate(for: audio)
        interfaceController?.pushTemplate(chapterList, animated: true, completion: nil)
    }
}
