//
//  AudioModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 19/06/23.
//

import Foundation

struct AudioModel: Codable {
    var title = String()
    var albumName = String()
    var artist = String()
    var duration: Double = .zero
    var currentTime: Double = .zero
    var imageData: Data?
    var chapters = [String]()
    var url: URL?
}

extension AudioModel {
    func copyWith(
        title: String? = nil,
        albumName: String? = nil,
        artist: String? = nil,
        duration: Double? = nil,
        currentTime: Double? = nil,
        imageData: Data? = nil,
        chapters: [String]? = nil,
        url: URL? = nil
    ) -> AudioModel {
        .init(
            title: title ?? self.title,
            albumName: albumName ?? self.albumName,
            artist: artist ?? self.artist,
            duration: duration ?? self.duration,
            currentTime: currentTime ?? self.currentTime,
            imageData: imageData ?? self.imageData,
            chapters: chapters ?? self.chapters,
            url: url ?? self.url
        )
    }
}
