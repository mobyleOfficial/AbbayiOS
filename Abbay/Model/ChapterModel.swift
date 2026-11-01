//
//  ChapterModel.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 02/07/23.
//

import Foundation

struct ChapterModel: Codable {
    var title = String()
    var startTime: Double = .zero
    var duration: Double = .zero
    var remoteURL: URL?
    var expectedBytes: Int64 = 0
    /// How far into the chapter listening got, in seconds from its start (#299). `nil` until the
    /// chapter is first played on a version that records it; its `duration` once played through.
    var resumeOffset: Double?

    var endTime: Double {
        startTime + duration
    }

    /// Closer than this to a chapter's end counts as listened to the end: a tap starts it over.
    static let finishedTolerance: Double = 5

    /// Whether `bookTime` is in the chapter's last `finishedTolerance` seconds or past its end: a
    /// tap on the chapter there starts it over rather than playing on (#299).
    func isFinished(at bookTime: Double) -> Bool {
        bookTime >= endTime - Self.finishedTolerance
    }

    /// Where playing this chapter starts (#299): where it was left, unless it was never started or
    /// was listened to the end, which start it from the beginning.
    var resumeTime: Double {
        guard let resumeOffset, resumeOffset > 0, resumeOffset < duration - Self.finishedTolerance else {
            return startTime
        }
        return startTime + resumeOffset
    }
}

/// Where listening got in one chapter (#299): its index in the book and the seconds from its start.
struct ChapterPosition: Equatable {
    let index: Int
    let offset: Double
}
