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
    var chapters = [ChapterModel]()
    var url: URL?

    func currentChapter(for time: Double) -> Int {
        chapters.firstIndex { chapter in
            chapter.startTime > time
        } ?? 1
    }
}

extension AudioModel {
    func copyWith<Value>(
        _ key: WritableKeyPath<Self, Value>,
        value: Value
    ) -> AudioModel {
        var copy = self
        copy[keyPath: key] = value
        return copy
    }
}
