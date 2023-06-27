//
//  FloatingPlayerModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 27/06/23.
//

import Foundation

final class FloatingPlayerModel: ObservableObject {
    // MARK: - Properties
    let title: String
    let duration: Double
    let imageData: Data?
    let url: URL?
    let chapters: [String]
    var currentChapter: String

    // MARK: - Observed properties
    @Published
    private(set) var player = Player()
    @Published
    var currentTime: Double = 0
    @Published
    var isPlaying: Bool = false

    // MARK: - Init
    init(
        title: String,
        duration: Double,
        imageData: Data?,
        url: URL?,
        chapters: [String] = [String](),
        currentChapter: String = String()
    ) {
        self.title = title
        self.duration = duration
        self.imageData = imageData
        self.url = url
        self.chapters = chapters
        self.currentChapter = currentChapter

        defer {
            player.addObserver(interval: 1) { [weak self] time in
                guard let self = self else { return }
                self.currentTime = time.seconds
                self.isPlaying = self.player.isPlaying(self.url)
            }
        }
    }
}
