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
    var bookmarkData: Data?

    func currentChapter(for time: Double) -> Int {
        chapters.firstIndex { chapter in
            chapter.startTime..<chapter.endTime ~= time + 1
        } ?? 0
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
