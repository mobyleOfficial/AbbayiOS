//
//  ReadAlongTranscribing.swift
//  Abbay
//

import Foundation

/// Whether a language's speech model can be used now, after a download, or not at all.
enum ReadAlongModelStatus: Equatable {
    case installed
    case downloadable
    case unsupported
}

/// What a transcription run hands over as it goes: the lines it finished, and the book time it has
/// now covered, silence included, so the session can save progress even where nobody speaks.
struct ReadAlongChunk: Equatable {
    let lines: [ReadAlongLine]
    let covered: ReadAlongSpan
}

/// The speech engine behind read-along, behind a protocol so the session and UI tests can run on a
/// stub (`StubReadAlongTranscriber`) and on systems without the iOS 26 engine. Locale ids are
/// BCP-47 with a hyphen ("en-US").
protocol ReadAlongTranscribing: AnyObject, Sendable {
    /// Sorted, so callers that take the first match pick the same locale every time.
    func supportedLocales() async -> [String]
    /// Sorted, as `supportedLocales()`.
    func installedLocales() async -> [String]
    func modelStatus(locale: String) async -> ReadAlongModelStatus
    func installModel(locale: String) async throws
    /// Transcribes forward from `startTime` (book time), segment after segment, until the end
    /// of the book, the first segment not on the device (then finishes), or cancellation.
    /// Each chunk carries finished lines and the book-time span now covered.
    func transcribe(_ source: ReadAlongAudioSource, from startTime: Double, locale: String)
        -> AsyncThrowingStream<ReadAlongChunk, Error>
    /// Mean word confidence of `seconds` of audio from `startTime`, for language detection.
    func confidence(
        _ source: ReadAlongAudioSource,
        from startTime: Double,
        seconds: Double,
        locale: String
    ) async throws -> Double
}

enum ReadAlongTranscriberError: Error, Equatable {
    /// No speech model exists for the locale on this device.
    case unsupportedLocale(String)
}

extension ReadAlongAudioSource {
    /// One file to read for a run: the segment, and how far into its file to start.
    struct Reading: Equatable {
        let segment: Segment
        /// Seconds into the file.
        let offset: Double

        /// Book time of the first sample read: the engine's 0 s for this file.
        var bookStart: Double { segment.bookStart + offset }
        var bookEnd: Double { segment.bookStart + segment.duration }
    }

    /// The files a run starting at `startTime` reads, in order: the one holding `startTime` from
    /// that point, then each following one from its start, stopping before the first that isn't on
    /// the device. Read-along never fetches audio, so a missing chapter ends the run there.
    /// Empty when `startTime` is past the end or its own file is missing.
    func readings(from startTime: Double) -> [Reading] {
        guard let first = segments.lastIndex(where: { $0.bookStart <= startTime }) ?? segments.indices.first
        else { return [] }
        var result: [Reading] = []
        for index in segments.indices[first...] {
            let segment = segments[index]
            guard segment.fileURL != nil else { break }
            let offset = index == first ? max(0, startTime - segment.bookStart) : 0
            guard offset < segment.duration else { continue }
            result.append(Reading(segment: segment, offset: offset))
        }
        return result
    }
}

extension ReadAlongLine {
    /// The same line `seconds` later: the engine times from where it began reading, the transcript
    /// in book time.
    func shifted(by seconds: Double) -> ReadAlongLine {
        ReadAlongLine(
            start: start + seconds,
            end: end + seconds,
            words: words.map { ReadAlongWord(text: $0.text, start: $0.start + seconds, end: $0.end + seconds) }
        )
    }
}
