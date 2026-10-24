//
//  MockDependencyContainer.swift
//  AbbayTests
//

@testable import Abbay

final class MockDependencyContainer: DependencyContainerProtocol {
    let player: PlayerProtocol
    let loadAudio: LoadAudioUseCaseProtocol
    let loadAllAudios: LoadAllAudiosUseCaseProtocol
    let downloads: BookDownloadManagerProtocol
    let playback: PlaybackCenter
    let downloadStates: DownloadStateStore
    let settings: AppSettings

    init(player: PlayerProtocol,
         loadAudio: LoadAudioUseCaseProtocol,
         loadAllAudios: LoadAllAudiosUseCaseProtocol,
         downloads: BookDownloadManagerProtocol = MockBookDownloadManager(),
         settings: AppSettings = AppSettings(store: InMemoryKeyValueStore())) {
        self.settings = settings
        self.player = player
        self.loadAudio = loadAudio
        self.loadAllAudios = loadAllAudios
        self.downloads = downloads
        self.downloadStates = DownloadStateStore(downloads: downloads)
        self.playback = PlaybackCenter(player: player, loadAudio: loadAudio)
    }
}
