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
    private let deleteAudioUseCase: DeleteAudioUseCaseProtocol

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
        loadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase(repository: LoadAllAudiosRepository()),
        deleteAudioUseCase: DeleteAudioUseCaseProtocol = DeleteAudioUseCase()
    ) {
        self.playerObserver = playerObserver
        self.loadAllAudiosUseCase = loadAllAudiosUseCase
        self.deleteAudioUseCase = deleteAudioUseCase
        defer {
            audioList = loadAllAudiosUseCase.execute()
            self.playerObserver.subscribeToPlayUrlPublisher { [weak self] newItem in
               self?.selectedAudio = newItem
            }
        }
    }

    // MARK: - Methods
    func deleteAudio(_ audio: AudioModel) {
        deleteAudioUseCase.execute(audio)
        audioList.removeAll { $0.url == audio.url }
    }
}
