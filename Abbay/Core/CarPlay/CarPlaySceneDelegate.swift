//
//  CarPlaySceneDelegate.swift
//  Abbay
//

import CarPlay
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
    lazy var playerObserver: PlayerObserverProtocol = PlayerObserver(DependencyContainer.shared.player)

    // MARK: - State
    //
    // Internal rather than private so tests can assert it. `CPInterfaceController` has no public
    // initialiser, so `didConnect` cannot be driven from a test and this state is otherwise
    // unreachable -- see #96.
    private(set) var audioItems: [AudioModel] = []
    private(set) var currentAudio: AudioModel?
    private(set) var currentPlayingItem: CPListItem?

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.isUpNextButtonEnabled = true
        nowPlaying.upNextTitle = Localizable.chapterSelectionTitle.localized
        nowPlaying.add(self)

        setupObservers()

        interfaceController.setRootTemplate(buildLibraryTemplate(), animated: true, completion: nil)

        // Resolve current audio if already playing before CarPlay connected
        if let playerUrl = playerObserver.player.url {
            currentAudio = audioItems.first { $0.url == playerUrl }
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        CPNowPlayingTemplate.shared.remove(self)
        playerObserver.cancelTimeSubscription()
        self.interfaceController = nil
        self.audioItems = []
        self.currentAudio = nil
        self.currentPlayingItem = nil
    }

    // MARK: - Observers

    func setupObservers() {
        playerObserver.subscribeToPlayUrlPublisher { [weak self] audio in
            guard let self else { return }
            // Order matters: both chapter-list entry points gate on `currentAudio`.
            self.currentAudio = audio
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
    }

    // MARK: - Template Builders

    func buildLibraryTemplate() -> CPListTemplate {
        audioItems = loadAllAudiosUseCase.execute()

        let listItems = audioItems.map { audio in
            buildListItem(for: audio)
        }

        let section = CPListSection(items: listItems)
        let template = CPListTemplate(title: Localizable.libraryTitle.localized, sections: [section])

        return template
    }

    func buildListItem(for audio: AudioModel) -> CPListItem {
        let detailText = audio.artist.isEmpty ? audio.albumName : audio.artist

        let item = CPListItem(
            text: audio.title,
            detailText: detailText
        )

        if let imageData = audio.imageData, let image = UIImage(data: imageData) {
            item.setImage(image)
        } else {
            item.setImage(UIImage(systemName: "book.closed"))
        }

        if audio.duration > 0 {
            item.playbackProgress = CGFloat(audio.currentTime / audio.duration)
        }

        // Track the currently playing item for live progress updates
        if audio.url == playerObserver.player.url {
            currentPlayingItem = item
        }

        item.handler = { [weak self] selectedItem, completion in
            self?.currentPlayingItem = selectedItem as? CPListItem
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

    func handleAudioSelection(_ audio: AudioModel) {
        // Fetch fresh model from CoreData to get the latest saved currentTime
        var freshAudio = loadAudioUseCase.execute(url: audio.url) ?? audio
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
