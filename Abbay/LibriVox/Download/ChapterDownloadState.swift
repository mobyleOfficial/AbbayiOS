//
//  ChapterDownloadState.swift
//  Abbay
//

import Foundation

/// What the UI shows for one chapter: ✓, a percentage, "waiting", or "failed, retry".
enum ChapterDownloadState: Equatable {
    case downloaded
    case downloading(fraction: Double)
    /// Not started yet, paused, held by the system (e.g. waiting for Wi-Fi), or waiting to retry.
    case waiting
    /// Failed every automatic retry. Restarts when the user retries it or the network comes back.
    case failed
}

/// Download progress of one LibriVox book.
struct BookDownloadState: Equatable {
    var chapters: [ChapterDownloadState]
    var isPaused: Bool
    /// Bytes-weighted over each chapter's expected bytes; falls back to chapter count when the
    /// sizes are unknown (all 0).
    var fraction: Double

    var isComplete: Bool {
        chapters.allSatisfy { $0 == .downloaded }
    }
}

extension BookDownloadState {
    /// Builds the state and computes `fraction` from the chapters' expected sizes.
    init(chapters: [ChapterDownloadState], expectedBytes: [Int64], isPaused: Bool) {
        self.chapters = chapters
        self.isPaused = isPaused
        fraction = Self.fraction(of: chapters, expectedBytes: expectedBytes)
    }

    private static func fraction(of chapters: [ChapterDownloadState], expectedBytes: [Int64]) -> Double {
        guard !chapters.isEmpty else { return 0 }
        let done: [Double] = chapters.map { state in
            switch state {
            case .downloaded: return 1
            case let .downloading(fraction): return fraction
            case .waiting, .failed: return 0
            }
        }
        let sizes = chapters.indices.map { Double(expectedBytes.indices.contains($0) ? max(expectedBytes[$0], 0) : 0) }
        let total = sizes.reduce(0, +)
        guard total > 0 else {
            return done.reduce(0, +) / Double(chapters.count)
        }
        return zip(done, sizes).map(*).reduce(0, +) / total
    }
}
