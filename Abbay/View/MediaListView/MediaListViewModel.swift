//
//  MediaListViewModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import AppIntents
import Foundation

final class MediaListViewModel: ObservableObject {
    // MARK: - Properties
    private let fileLoader: FileLoaderProtocol
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
        loadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase(),
        deleteAudioUseCase: DeleteAudioUseCaseProtocol = DeleteAudioUseCase(),
        fileLoader: FileLoaderProtocol = FileLoader()
    ) {
        self.playerObserver = playerObserver
        self.loadAllAudiosUseCase = loadAllAudiosUseCase
        self.deleteAudioUseCase = deleteAudioUseCase
        self.fileLoader = fileLoader
        defer {
            audioList = loadAllAudiosUseCase.execute()
            LibrarySnapshotWriter.shared.write(audios: audioList)
            self.playerObserver.subscribeToPlayUrlPublisher { [weak self] newItem in
                self?.selectedAudio = newItem
            }
        }
    }

    // MARK: - Methods
    func deleteAudio(_ audio: AudioModel) {
        deleteAudioUseCase.execute(audio)
        audioList.removeAll { $0.url == audio.url }
        LibrarySnapshotWriter.shared.write(audios: audioList)
    }

    @MainActor
    func importAudio(from urls: [URL]) async {
        let newFiles = await fileLoader.load(urls: urls)
        for file in newFiles where !audioList.contains(where: { $0.url == file.url }) {
            audioList.append(file)
        }
        LibrarySnapshotWriter.shared.write(audios: audioList)
        AbbayAppShortcuts.updateAppShortcutParameters()
    }
}
