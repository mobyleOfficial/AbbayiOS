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

    // MARK: - Observed properties
    @Published
    var audioList = [AudioModel]()
    @Published
    var selectedAudio: AudioModel?
    @Published
    var isShowingFilePicker = false

    // MARK: - Init
    init() {
        defer {
            let files = Cache<URL, AudioModel>.load(withName: FileLoader.cacheKey)
            let times = Cache<URL, Double>.load(withName: Player.cacheKey)
            let models = files.getAllPairs().compactMap { key, value in
                value.copyWith(\.currentTime, value: times[key] ?? .zero)
            }
            audioList = models.sorted { $0.title.lowercased() < $1.title.lowercased() }
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
