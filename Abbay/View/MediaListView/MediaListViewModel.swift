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
    let player = Player()
    let mediaSelection = MediaSelection()
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
    init(loadAllAudiosUseCase: LoadAllAudiosUseCaseProtocol = LoadAllAudiosUseCase()) {
        self.loadAllAudiosUseCase = loadAllAudiosUseCase
        defer {
            audioList = loadAllAudiosUseCase.execute()
            mediaSelection.subscribe { [weak self] selectedAudio in
                self?.selectedAudio = selectedAudio
            }
        }
    }
}

// MARK: - MediaSelection
final class MediaSelection {
    typealias SelectionCallback = (AudioModel?) -> Void

    private var subscriptions = [SelectionCallback]()

    func subscribe(with subscription: @escaping SelectionCallback) {
        subscriptions.append(subscription)
    }

    func select(_ model: AudioModel) {
        for subscription in subscriptions {
            subscription(model)
        }
    }
}
