//
//  CarPlaySceneDelegate.swift
//  Abbay
//

import CarPlay
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    // MARK: - Properties

    private var interfaceController: CPInterfaceController?
    private let loadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase()
    private let loadAudioUseCase: LoadAudioUseCaseProtocol = LoadAudioUseCase()
    private let playerObserver: PlayerObserverProtocol = PlayerObserver(DependencyContainer.shared.player)
    private var audioItems: [AudioModel] = []
    private var currentAudio: AudioModel?
    private var currentPlayingItem: CPListItem?

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.isUpNextButtonEnabled = true
        nowPlaying.upNextTitle = "Chapters"
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

    private func setupObservers() {
        playerObserver.subscribeToPlayUrlPublisher { [weak self] audio in
            self?.currentAudio = audio
        }

        playerObserver.subscribeToTimePublisher { [weak self] time in
            guard let self, let audio = self.currentAudio, audio.duration > 0 else { return }
            let progress = CGFloat(time.seconds / audio.duration)
            self.currentPlayingItem?.playbackProgress = progress
        }
    }

    // MARK: - Template Builders

    private func buildLibraryTemplate() -> CPListTemplate {
        audioItems = loadAllAudiosUseCase.execute()

        let listItems = audioItems.map { audio in
            buildListItem(for: audio)
        }

        let section = CPListSection(items: listItems)
        let template = CPListTemplate(title: "Library", sections: [section])

        return template
    }

    private func buildListItem(for audio: AudioModel) -> CPListItem {
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

    private func buildChapterListTemplate(for audio: AudioModel) -> CPListTemplate {
        let player = playerObserver.player
        let currentChapterIndex = audio.currentChapter(for: player.currentTime)

        let items = audio.chapters.enumerated().map { index, chapter -> CPListItem in
            let item = CPListItem(
                text: chapter.title,
                detailText: formatTime(chapter.startTime)
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
        return CPListTemplate(title: "Chapters", sections: [section])
    }

    // MARK: - Playback

    private func handleAudioSelection(_ audio: AudioModel) {
        // Fetch fresh model from CoreData to get the latest saved currentTime
        var freshAudio = loadAudioUseCase.execute(url: audio.url) ?? audio
        playerObserver.player.play(&freshAudio)

        interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
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
