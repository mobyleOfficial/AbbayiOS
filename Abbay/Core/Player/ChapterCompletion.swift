//
//  ChapterCompletion.swift
//  Abbay
//

import Foundation

/// Tells which chapters playback ran through to their end (#299), from the player's ticks: a
/// playing tick in a later chapter of the same book, a small step after the last one and with no
/// seek in between, finished every chapter from the last tick's to the one before this tick's. A
/// seek (a chapter tap, a skip, the scrubber) leaves the chapter it moved off unfinished, at the
/// offset saved for it.
final class ChapterCompletion {
    /// The periodic observer ticks every second of playback; a bigger step is a jump. Leaves room
    /// for a LibriVox file a few seconds shorter than its chapter's listed duration.
    static let maxStep: Double = 10

    /// The book, chapter and book time of the last playing tick.
    private struct Tick {
        let url: URL?
        let index: Int
        let time: Double
    }

    private var last: Tick?
    private var hasJumped = false

    /// A seek was asked for. The tick after it may still report the old time, which `maxStep`
    /// then catches on the tick after that.
    func jumped() {
        hasJumped = true
    }

    /// The chapters finished since the last tick, in order; empty for most ticks.
    func tick(_ model: AudioModel?, bookTime: Double, isPlaying: Bool) -> [Int] {
        guard isPlaying, let model, let index = model.currentChapter(for: bookTime) else { return [] }
        defer {
            last = Tick(url: model.url, index: index, time: bookTime)
            hasJumped = false
        }
        guard !hasJumped, let last, last.url == model.url, last.index < index else { return [] }
        let step = bookTime - last.time
        guard step > 0, step <= Self.maxStep else { return [] }
        return Array(last.index..<index)
    }
}
