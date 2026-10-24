//
//  PlaybackClock.swift
//  Abbay
//

import Foundation
import Observation

/// The ticking half of playback, updated about once a second. Only the mini bar, the open details
/// screen and the playing row's progress sub-view read it; rows that aren't playing never do, so a
/// tick costs them nothing.
@Observable
final class PlaybackClock {
    private(set) var bookTime: Double = 0
    private(set) var currentChapter: Int = 0

    /// Assigns only what changed: Observation notifies on every set, even with an equal value.
    func update(bookTime: Double, currentChapter: Int) {
        if bookTime != self.bookTime { self.bookTime = bookTime }
        if currentChapter != self.currentChapter { self.currentChapter = currentChapter }
    }
}
