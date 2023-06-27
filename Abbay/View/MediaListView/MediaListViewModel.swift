//
//  MediaListViewModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import Foundation

final class MediaListViewModel: ObservableObject {
    // MARK: - Properties
    var fileLoader = FileLoader()

    // MARK: - Observed properties
    @Published
    private(set) var player = Player()
    @Published
    var audioList = [AudioModel]()
    @Published
    var selectedAudio: AudioModel?
    @Published
    var isShowingFilePicker = false
}
