//
//  BookTimeline.swift
//  Abbay
//

import Foundation

/// Maps between a book-wide time and a (chapter, offset) pair.
/// Based on each chapter's `startTime`, so gaps or overlaps in the source
/// playtimes cannot accumulate drift.
struct BookTimeline: Equatable {
    struct Position: Equatable {
        let chapterIndex: Int
        let offset: Double
    }

    private struct Span: Equatable {
        let start: Double
        let duration: Double
    }

    private let spans: [Span]

    init(chapters: [ChapterModel]) {
        spans = chapters.map { Span(start: $0.startTime, duration: $0.duration) }
    }

    func position(at bookTime: Double) -> Position {
        guard let last = spans.last else {
            return Position(chapterIndex: 0, offset: max(bookTime, 0))
        }
        guard bookTime > 0 else {
            return Position(chapterIndex: 0, offset: 0)
        }
        if let index = spans.lastIndex(where: { $0.start <= bookTime && bookTime < $0.start + $0.duration }) {
            return Position(chapterIndex: index, offset: bookTime - spans[index].start)
        }
        if bookTime >= last.start + last.duration {
            return Position(chapterIndex: spans.count - 1, offset: last.duration)
        }
        // In a gap between chapters: snap to the start of the next one.
        let next = spans.firstIndex(where: { $0.start > bookTime }) ?? spans.count - 1
        return Position(chapterIndex: next, offset: 0)
    }

    func bookTime(chapterIndex: Int, offset: Double) -> Double {
        guard spans.indices.contains(chapterIndex) else { return offset }
        return spans[chapterIndex].start + offset
    }
}
