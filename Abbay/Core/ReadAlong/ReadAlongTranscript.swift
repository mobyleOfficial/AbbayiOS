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
    mutating func add(_ newLines: [ReadAlongLine], covering span: ReadAlongSpan) {
        let kept = lines.filter { existing in
            !newLines.contains { abs($0.start - existing.start) <= Self.duplicateTolerance }
        }
        lines = (kept + newLines).sorted { $0.start < $1.start }
        mergeCovered(span)
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
