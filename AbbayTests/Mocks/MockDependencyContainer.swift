//
//  MockDependencyContainer.swift
//  AbbayTests
//

@testable import Abbay

final class MockDependencyContainer: DependencyContainerProtocol {
    let player: PlayerProtocol
    let loadAudio: LoadAudioUseCaseProtocol
    let loadAllAudios: LoadAllAudiosUseCaseProtocol

    init(player: PlayerProtocol,
         loadAudio: LoadAudioUseCaseProtocol,
         loadAllAudios: LoadAllAudiosUseCaseProtocol) {
        self.player = player
        self.loadAudio = loadAudio
        self.loadAllAudios = loadAllAudios
    }
}
