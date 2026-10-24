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
    private let loadAudioUseCase: LoadAudioUseCaseProtocol
    /// The book the player last announced, so a switch knows which book it left.
    private var loadedURL: URL?

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
        fileLoader: FileLoaderProtocol = FileLoader(),
        loadAudioUseCase: LoadAudioUseCaseProtocol = LoadAudioUseCase()
    ) {
        self.playerObserver = playerObserver
        self.loadAllAudiosUseCase = loadAllAudiosUseCase
        self.deleteAudioUseCase = deleteAudioUseCase
        self.fileLoader = fileLoader
        self.loadAudioUseCase = loadAudioUseCase
        self.loadedURL = playerObserver.player.url
        defer {
            audioList = loadAllAudiosUseCase.execute()
            LibrarySnapshotWriter.shared.write(audios: audioList)
            self.playerObserver.subscribeToPlayUrlPublisher { [weak self] newItem in
                Self.onMain { self?.bookLoaded(newItem) }
            }
        }
    }

    // MARK: - Methods
    /// Rows are built from `audioList`, which loads once. On a book switch, re-read both books
    /// from storage: the outgoing one so its row shows (and a replay resumes from) where it
    /// stopped -- the player saves its position before announcing the next book -- and the
    /// incoming one so later presses pass the bookmark the player just made. Once per switch,
    /// never per tick.
    private func bookLoaded(_ book: AudioModel) {
        selectedAudio = book
        let outgoing = loadedURL
        loadedURL = book.url
        if outgoing != book.url {
            refreshFromStorage(outgoing)
        }
        refreshFromStorage(book.url)
    }

    private func refreshFromStorage(_ url: URL?) {
        guard let url,
              let index = audioList.firstIndex(where: { $0.url == url }),
              let stored = loadAudioUseCase.execute(url: url) else { return }
        audioList[index] = stored
    }

    /// The player can announce a book off the main thread (SiriKit); `audioList` drives the UI.
    private static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

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

    /// A LibriVox book the details page just saved. Refreshed like an import.
    func addLibriVoxBook(_ book: AudioModel) {
        guard !audioList.contains(where: { $0.url == book.url }) else { return }
        audioList.append(book)
        LibrarySnapshotWriter.shared.write(audios: audioList)
        AbbayAppShortcuts.updateAppShortcutParameters()
    }
}
