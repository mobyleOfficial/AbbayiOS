//
//  MediaListViewModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import Foundation
import Combine

final class MediaListViewModel: ObservableObject {
    // MARK: - Properties
    let fileLoader = FileLoader()
    let player = Player()
    lazy var playerObserver = PlayerObserver(player)
    private let loadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol
    private var cancellables = Set<AnyCancellable>()

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
    init(loadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase()) {
        self.loadAllAudiosUseCase = loadAllAudiosUseCase
        defer {
            audioList = loadAllAudiosUseCase.execute()
            self.playerObserver.subscribeToPlayUrlPublisher { [weak self] newItem in
               self?.selectedAudio = newItem
            }
            setupLiveActivityNotifications()
        }
    }

    // MARK: - Live Activity Controls
    private func setupLiveActivityNotifications() {
        NotificationCenter.default.publisher(for: .liveActivityPlayPause)
            .sink { [weak self] _ in
                guard let self = self, var selectedAudio = self.selectedAudio else { return }
                if self.player.isPlaying(selectedAudio.url) {
                    self.player.pause()
                } else {
                    self.player.play(&selectedAudio)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .liveActivitySkipForward)
            .sink { [weak self] _ in
                self?.player.forward(withSeconds: 15)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .liveActivitySkipBackward)
            .sink { [weak self] _ in
                self?.player.backward(withSeconds: 15)
            }
            .store(in: &cancellables)
    }
}
