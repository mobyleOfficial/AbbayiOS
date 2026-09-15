//
//  DependencyContainer.swift
//  Abbay
//

import Foundation

protocol DependencyContainerProtocol {
    var player: PlayerProtocol { get }
    var loadAudio: LoadAudioUseCaseProtocol { get }
    var loadAllAudios: LoadAllAudiosUseCaseProtocol { get }
}

final class DependencyContainer: DependencyContainerProtocol {
    private static var _shared: DependencyContainerProtocol?

    static var shared: DependencyContainerProtocol {
        guard let container = _shared else {
            fatalError("DependencyContainer not configured. Call configure() in AppDelegate.")
        }
        return container
    }

    static func configure(with container: DependencyContainerProtocol? = nil) {
        _shared = container ?? DependencyContainer()
    }

    static func reset() {
        _shared = nil
    }

    let player: PlayerProtocol
    let loadAudio: LoadAudioUseCaseProtocol
    let loadAllAudios: LoadAllAudiosUseCaseProtocol

    private init() {
        self.player = Player()
        self.loadAudio = LoadAudioUseCase()
        self.loadAllAudios = LoadAllAudiosUseCase()
    }
}
