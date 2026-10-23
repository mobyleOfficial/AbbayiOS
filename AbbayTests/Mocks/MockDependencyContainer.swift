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

    init(player: PlayerProtocol,
         loadAudio: LoadAudioUseCaseProtocol,
         loadAllAudios: LoadAllAudiosUseCaseProtocol,
         downloads: BookDownloadManagerProtocol = MockBookDownloadManager()) {
        self.player = player
        self.loadAudio = loadAudio
        self.loadAllAudios = loadAllAudios
        self.downloads = downloads
    }
}
