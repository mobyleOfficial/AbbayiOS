//
//  ReadAlongTranscript.swift
//  Abbay
//

import Foundation

/// One recognised word. Times are book time in seconds, so a transcript stays valid whatever
/// chapter file or playback speed produced it.
struct ReadAlongWord: Codable, Equatable {
    let text: String
    let start: Double
    let end: Double
}

/// A run of words the recogniser returned as one phrase; the unit the player shows and scrolls.
struct ReadAlongLine: Codable, Equatable {
    let start: Double
    let end: Double
    let words: [ReadAlongWord]

    /// Derived, not stored: the words are the single source of truth, so `Codable` synthesis
    /// skips it and the two can never disagree.
    var text: String { words.map(\.text).joined(separator: " ") }
}

/// A stretch of book time that has been transcribed, half-open: `start <= time < end`.
struct ReadAlongSpan: Codable, Equatable {
    var start: Double
    var end: Double
}

/// What to highlight: a line, and the word being spoken when there is one.
struct ReadAlongPosition: Equatable {
    let line: Int
    let word: Int?
}

/// Everything transcribed so far for one book, in book time. Transcription arrives in runs
/// (ahead of the playhead, after a seek, resumed after a pause), so `add` has to accept runs in
/// any order and overlapping ones, and `covered` records which stretches are already done.
struct ReadAlongTranscript: Codable, Equatable {
    /// How close two line starts must be to count as the same line seen by two runs.
    private static let duplicateTolerance = 0.05

    /// BCP-47, e.g. `en-US`.
    var language: String
    /// Sorted by `start`, no duplicates.
    private(set) var lines: [ReadAlongLine] = []
    /// Merged and sorted: book time already transcribed.
    private(set) var covered: [ReadAlongSpan] = []

    init(language: String) {
        self.language = language
    }

    /// Merges a run into the transcript. An incoming line replaces any stored line starting within
    /// 0.05 s of it, so overlapping runs re-transcribing the same audio do not duplicate lines.
    /// Spans that touch or overlap are merged.
    ///
    /// A chunk is a few lines and a whole book's transcript thousands, and a chunk arrives every
    /// moment while a run goes: only the stored lines near the chunk's are touched (found by binary
    /// search) and the two sorted runs merged there, so the rest is never filtered or re-sorted.
    mutating func add(_ newLines: [ReadAlongLine], covering span: ReadAlongSpan) {
        mergeCovered(span)
        let incoming = newLines.sorted { $0.start < $1.start }
        guard let first = incoming.first, let last = incoming.last else { return }
        // Stored lines outside this window can't be within the tolerance of an incoming one.
        let low = firstLine { $0.start >= first.start - Self.duplicateTolerance }
        let high = firstLine { $0.start > last.start + Self.duplicateTolerance }
        var merged: [ReadAlongLine] = []
        merged.reserveCapacity(high - low + incoming.count)
        var next = 0
        for existing in lines[low..<high] {
            while next < incoming.count, incoming[next].start <= existing.start {
                merged.append(incoming[next])
                next += 1
            }
            // The incoming lines nearest to it are the last one placed and the next one.
            let isReplaced = [next - 1, next].contains { index in
                incoming.indices.contains(index)
                    && abs(incoming[index].start - existing.start) <= Self.duplicateTolerance
            }
            if !isReplaced { merged.append(existing) }
        }
        merged.append(contentsOf: incoming[next...])
        lines.replaceSubrange(low..<high, with: merged)
    }

    func isCovered(_ time: Double) -> Bool {
        covered.contains { $0.start <= time && time < $0.end }
    }

    /// The line being spoken is the last one that has started; the gap after it holds that line
    /// rather than blanking the text. `word` is nil between words.
    func position(at time: Double) -> ReadAlongPosition? {
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        guard low > 0 else { return nil }
        let index = low - 1
        let word = lines[index].words.firstIndex { $0.start <= time && time < $0.end }
        return ReadAlongPosition(line: index, word: word)
    }

    /// The index of the first line for which `isAtOrPast` holds (it must hold for every line after
    /// it too); `lines.count` when none does.
    private func firstLine(where isAtOrPast: (ReadAlongLine) -> Bool) -> Int {
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if isAtOrPast(lines[mid]) { high = mid } else { low = mid + 1 }
        }
        return low
    }

    private mutating func mergeCovered(_ span: ReadAlongSpan) {
        guard span.end > span.start else { return }
        var merged: [ReadAlongSpan] = []
        for next in (covered + [span]).sorted(by: { $0.start < $1.start }) {
            if var last = merged.last, next.start <= last.end {
                last.end = max(last.end, next.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(next)
            }
        }
        covered = merged
    }
}
