//
//  AudioModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 19/06/23.
//

import Foundation

struct AudioModel {
    var title = String()
    var albumName = String()
    var artist = String()
    var duration: Double = .zero
    var currentTime: Double = .zero
    var imageData: Data?
    var chapters = [ChapterModel]()
    var url: URL?
    var bookmarkData: Data?
    /// The book's archive.org identifier (e.g. `alice_in_wonderland_librivox`), not a LibriVox
    /// catalog ID: not every archive item has one. Named for the source; nil for imported files.
    var librivoxID: String?
    var allowsCellularDownload = false
    var isDownloadPaused = false
    var totalBytes: Int64 = 0

    var isLibriVox: Bool {
        librivoxID != nil
    }

    func currentChapter(for time: Double) -> Int {
        chapters.firstIndex { chapter in
            chapter.startTime..<chapter.endTime ~= time + 1
        } ?? 0
    }
}
