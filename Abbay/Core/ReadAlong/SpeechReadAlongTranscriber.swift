//
//  SpeechReadAlongTranscriber.swift
//  Abbay
//

import AVFoundation
import Foundation
import Speech

/// Read-along's real engine: iOS 26's on-device `SpeechAnalyzer` with a `SpeechTranscriber`,
/// reading the book's own files. No microphone and no speech authorization: file transcription with
/// this API never asks (the spike checked `.notDetermined` before and after, with no Info.plist key).
///
/// Only final results are asked for: a line is shown once, never rewritten, and the engine runs far
/// ahead of playback (about 70× real time on an iPhone 15), so volatile guesses would buy nothing.
@available(iOS 26, *)
final class SpeechReadAlongTranscriber: ReadAlongTranscribing {
    typealias Reading = ReadAlongAudioSource.Reading

    // MARK: Models

    func supportedLocales() async -> [String] {
        Self.ids(await SpeechTranscriber.supportedLocales)
    }

    func installedLocales() async -> [String] {
        Self.ids(await SpeechTranscriber.installedLocales)
    }

    /// Asks the asset inventory without creating an installation request, so checking never
    /// reserves a locale or starts a download.
    func modelStatus(locale id: String) async -> ReadAlongModelStatus {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id))
        else { return .unsupported }
        switch await AssetInventory.status(forModules: [Self.makeTranscriber(locale)]) {
        case .installed: return .installed
        case .supported, .downloading: return .downloadable
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    /// Downloads the language's model through iOS; returns at once when it is already installed.
    func installModel(locale id: String) async throws {
        let locale = try await Self.speechLocale(id)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [Self.makeTranscriber(locale)]) {
            try await request.downloadAndInstall()
        }
    }

    // MARK: Transcription

    func transcribe(_ source: ReadAlongAudioSource, from startTime: Double, locale id: String)
        -> AsyncThrowingStream<ReadAlongChunk, Error> {
        let readings = source.readings(from: startTime)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let locale = try await Self.speechLocale(id)
                    for reading in readings {
                        try Task.checkCancellation()
                        try await Self.transcribe(reading, locale: locale) { continuation.yield($0) }
                        try Task.checkCancellation()
                        // The whole file is done: the silence after its last line counts as covered.
                        continuation.yield(ReadAlongChunk(
                            lines: [],
                            covered: ReadAlongSpan(start: reading.bookStart, end: reading.bookEnd)
                        ))
                    }
                    continuation.finish()
                } catch {
                    // A cancelled run ends quietly: whatever the engine throws on the way out is
                    // a consequence of the cancel, not a failure to report.
                    continuation.finish(throwing: Task.isCancelled || error is CancellationError ? nil : error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Reads one file from `reading.offset` to the segment's end, handing over a chunk per final
    /// result.
    private static func transcribe(
        _ reading: Reading,
        locale: Locale,
        yield: @escaping @Sendable (ReadAlongChunk) -> Void
    ) async throws {
        try await withAccess(to: reading) { file in
            let transcriber = makeTranscriber(locale)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for try await result in transcriber.results where result.isFinal {
                            yield(chunk(for: result, in: reading))
                        }
                    }
                    do {
                        try await analyze(file, through: reading.bookEnd - reading.bookStart, with: analyzer)
                    } catch {
                        // Ends the results, or the group would wait on them forever.
                        await analyzer.cancelAndFinishNow()
                        throw error
                    }
                    try await group.waitForAll()
                }
            } onCancel: {
                // The analyzer doesn't watch task cancellation; without this a cancelled run would
                // keep reading the file to its end.
                Task { await analyzer.cancelAndFinishNow() }
            }
        }
    }

    /// Feeds `file`, from its current position, for `seconds`. A segment usually is its whole file
    /// (a LibriVox chapter, an imported book), and is read to the file's end. One that stops well
    /// inside its file (chapters within one file) is cut at its end, so the run neither transcribes
    /// the next chapter early nor spends time on it. The cut is only used inside the file: asked to
    /// finish past the end of the audio, the analyzer waits for input forever.
    private static func analyze(
        _ file: AVAudioFile,
        through seconds: Double,
        with analyzer: SpeechAnalyzer
    ) async throws {
        let sampleRate = file.processingFormat.sampleRate
        let remaining = Double(file.length - file.framePosition) / sampleRate
        if seconds < remaining - endOfFileMargin {
            let end = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(sampleRate))
            try await analyzer.start(inputAudioFile: file, finishAfterFile: false)
            try await analyzer.finalizeAndFinish(through: end)
        } else if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
    }

    /// A segment ending closer than this to its file's end is read to the end: chapter durations
    /// and decoded lengths disagree by a fraction of a second.
    private static let endOfFileMargin = 1.0

    /// The engine times from where it began reading; the transcript is in book time.
    private static func chunk(for result: SpeechTranscriber.Result, in reading: Reading) -> ReadAlongChunk {
        let end = min(reading.bookStart + result.range.end.seconds, reading.bookEnd)
        let lines = line(from: result).map { [$0.shifted(by: reading.bookStart)] } ?? []
        let covered = ReadAlongSpan(start: reading.bookStart, end: max(end, reading.bookStart))
        return ReadAlongChunk(lines: lines, covered: covered)
    }

    /// One line per result, one word per run that carries a time range. The line spans its words
    /// rather than the result's range, which can include the silence before the first word: tapping
    /// a line should land on its first word. Nil when no run is timed.
    private static func line(from result: SpeechTranscriber.Result) -> ReadAlongLine? {
        let text = result.text
        let words: [ReadAlongWord] = text.runs.compactMap { run in
            guard let range = run.audioTimeRange else { return nil }
            let word = String(text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { return nil }
            let start = range.start.seconds
            return ReadAlongWord(text: word, start: start, end: max(start, range.end.seconds))
        }
        guard let first = words.first, let last = words.last else { return nil }
        return ReadAlongLine(start: first.start, end: last.end, words: words)
    }

    // MARK: Detection

    /// Mean confidence of the words in the results that start within `seconds` of `startTime`.
    /// Reads only the file holding `startTime`; 0 when nothing was recognised. Only for installed
    /// models: without one Speech throws, misleadingly, "Audio format is not supported".
    func confidence(
        _ source: ReadAlongAudioSource,
        from startTime: Double,
        seconds: Double,
        locale id: String
    ) async throws -> Double {
        guard seconds > 0, let reading = source.readings(from: startTime).first else { return 0 }
        let locale = try await Self.speechLocale(id)
        return try await Self.withAccess(to: reading) { file in
            let transcriber = Self.makeTranscriber(locale)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            return try await withTaskCancellationHandler {
                try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
                var confidences: [Double] = []
                for try await result in transcriber.results where result.isFinal {
                    confidences += result.text.runs.compactMap(\.transcriptionConfidence)
                    if result.range.end.seconds >= seconds { break }
                }
                // Enough heard: stop reading the rest of the file.
                await analyzer.cancelAndFinishNow()
                guard !confidences.isEmpty else { return 0 }
                return confidences.reduce(0, +) / Double(confidences.count)
            } onCancel: {
                Task { await analyzer.cancelAndFinishNow() }
            }
        }
    }

    // MARK: Helpers

    private static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )
    }

    /// Speech's own locale for an id: "en-US" may be offered as "en_US".
    private static func speechLocale(_ id: String) async throws -> Locale {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id)) else {
            throw ReadAlongTranscriberError.unsupportedLocale(id)
        }
        return locale
    }

    /// Hyphenated BCP-47 ids, deduplicated and sorted.
    private static func ids(_ locales: [Locale]) -> [String] {
        Set(locales.map { $0.identifier(.bcp47) }).sorted()
    }

    /// Opens the reading's file positioned at its offset, inside the security scope an imported
    /// file needs, and closes the scope when `body` is done, however it ends (cancellation included).
    private static func withAccess<T>(
        to reading: Reading,
        _ body: (AVAudioFile) async throws -> T
    ) async throws -> T {
        guard let url = reading.segment.fileURL else { throw CocoaError(.fileNoSuchFile) }
        let didStart = reading.segment.isSecurityScoped && url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        let file = try AVAudioFile(forReading: url)
        let frame = AVAudioFramePosition((reading.offset * file.processingFormat.sampleRate).rounded(.down))
        file.framePosition = min(max(frame, 0), file.length)
        return try await body(file)
    }
}
