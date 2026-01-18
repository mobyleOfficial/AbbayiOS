//
//  MediaListViewModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import Foundation

final class MediaListViewModel: ObservableObject {
    // MARK: - Properties
    let fileLoader = FileLoader()
    private let playerObserver: PlayerObserverProtocol
    private let loadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol

    // MARK: - Observed properties
    @Published
    var audioList = [AudioModel]()
    @Published
    var selectedAudio: AudioModel?
    @Published
    var isShowingFilePicker = false
    @Published
    var tappedAudio: AudioModel?
    @Published
    var isShowingPlayer = false

    // MARK: - Init
    init(
        playerObserver: PlayerObserverProtocol = PlayerObserver(DependencyContainer.shared.player),
        loadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase(repository: LoadAllAudiosRepository())
    ) {
        self.playerObserver = playerObserver
        self.loadAllAudiosUseCase = loadAllAudiosUseCase
        defer {
            audioList = loadAllAudiosUseCase.execute()
            self.playerObserver.subscribeToPlayUrlPublisher { [weak self] newItem in
               self?.selectedAudio = newItem
            }
        }
    }
}
