//
//  AudiobookActivityAttributes.swift
//  AbbayWidget
//
//  Created for Live Activity support
//

import ActivityKit
import Foundation

struct AudiobookActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currentTime: Double
        var isPlaying: Bool
    }

    var title: String
    var author: String
    var duration: Double
    var imageData: Data?
    var currentChapter: Int
    var totalChapters: Int
}
