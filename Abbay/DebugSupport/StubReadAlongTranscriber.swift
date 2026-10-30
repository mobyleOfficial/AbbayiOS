//
//  StubReadAlongTranscriber.swift
//  Abbay
//

#if DEBUG
import Foundation

/// A transcriber with canned text, for the read-along session's unit tests and for UI tests under
/// `-seedReadAlong`, so neither needs a speech model, real audio, or iOS 26.
///
/// It keeps the protocol's contract the way the real engine does: a run covers forward from its
/// start through each following file on the device, stops before the first one that isn't, and
/// stops yielding once cancelled. Every knob is settable from a test and every call is recorded;
/// a lock guards both, since the protocol is `Sendable` and runs call in from any thread.
final class StubReadAlongTranscriber: ReadAlongTranscribing, @unchecked Sendable {
    /// Lines for the book time `from..<to`.
    typealias LineGenerator = @Sendable (_ from: Double, _ to: Double) -> [ReadAlongLine]

    private struct State {
        var supported = ["en-US", "pt-BR"]
        var installed = ["en-US", "pt-BR"]
        var statuses: [String: ReadAlongModelStatus] = [:]
        var confidences: [String: Double] = ["en-US": 0.9]
        var installError: Error?
        var installDelay: Duration?
        var confidenceErrors: Set<String> = []
        var runError: Error?
        var chunkDelay: Duration?
        var chunkSeconds = 60.0
        var lines: LineGenerator = { StubReadAlongTranscriber.seededLines(from: $0, to: $1) }
        var transcribeStarts: [Double] = []
        var installCalls: [String] = []
        var cancelledStarts: [Double] = []
    }

    private let lock = NSLock()
    private var state = State()

    // MARK: Knobs

    /// Sorted, as the real engine returns them.
    var supported: [String] {
        get { locked { $0.supported } }
        set { locked { $0.supported = newValue.sorted() } }
    }

    var installed: [String] {
        get { locked { $0.installed } }
        set { locked { $0.installed = newValue.sorted() } }
    }

    /// Overrides the status a locale would otherwise get from `installed` and `supported`.
    /// `installModel` clears the override, so a downloadable model reads as installed after it.
    var statuses: [String: ReadAlongModelStatus] {
        get { locked { $0.statuses } }
        set { locked { $0.statuses = newValue } }
    }

    /// Per locale; a locale not listed scores 0. The canned text is English, so English wins by
    /// default.
    var confidences: [String: Double] {
        get { locked { $0.confidences } }
        set { locked { $0.confidences = newValue } }
    }

    /// Thrown by `installModel`, after recording the call.
    var installError: Error? {
        get { locked { $0.installError } }
        set { locked { $0.installError = newValue } }
    }

    /// Waited before `installModel` returns, so a test can see the session downloading.
    var installDelay: Duration? {
        get { locked { $0.installDelay } }
        set { locked { $0.installDelay = newValue } }
    }

    /// Locales whose `confidence` throws, as the real engine may for a model that isn't installed.
    var confidenceErrors: Set<String> {
        get { locked { $0.confidenceErrors } }
        set { locked { $0.confidenceErrors = newValue } }
    }

    /// Thrown by every run after its first chunk: a run failing part way.
    var runError: Error? {
        get { locked { $0.runError } }
        set { locked { $0.runError = newValue } }
    }

    /// Waited before each chunk, so a test can catch a run in progress. Nil: no wait.
    var chunkDelay: Duration? {
        get { locked { $0.chunkDelay } }
        set { locked { $0.chunkDelay = newValue } }
    }

    /// Book time each chunk covers.
    var chunkSeconds: Double {
        get { locked { $0.chunkSeconds } }
        set { locked { $0.chunkSeconds = newValue } }
    }

    var lines: LineGenerator {
        get { locked { $0.lines } }
        set { locked { $0.lines = newValue } }
    }

    // MARK: Recorded calls

    /// The `startTime` of every `transcribe` call, in order.
    var transcribeStarts: [Double] { locked { $0.transcribeStarts } }
    /// The locale of every `installModel` call, in order.
    var installCalls: [String] { locked { $0.installCalls } }
    /// The `startTime` of every run that stopped because it was cancelled, in order.
    var cancelledStarts: [Double] { locked { $0.cancelledStarts } }

    // MARK: ReadAlongTranscribing

    func supportedLocales() async -> [String] { supported }

    func installedLocales() async -> [String] { installed }

    func modelStatus(locale: String) async -> ReadAlongModelStatus {
        locked { state in
            if let status = state.statuses[locale] { return status }
            if state.installed.contains(locale) { return .installed }
            return state.supported.contains(locale) ? .downloadable : .unsupported
        }
    }

    func installModel(locale: String) async throws {
        if let delay = installDelay { try await Task.sleep(for: delay) }
        let error: Error? = locked { state in
            state.installCalls.append(locale)
            guard state.installError == nil else { return state.installError }
            state.statuses[locale] = nil
            state.installed = Array(Set(state.installed + [locale])).sorted()
            return nil
        }
        if let error { throw error }
    }

    func transcribe(_ source: ReadAlongAudioSource, from startTime: Double, locale: String)
        -> AsyncThrowingStream<ReadAlongChunk, Error> {
        let (delay, step, generate, runError) = locked { state in
            state.transcribeStarts.append(startTime)
            return (state.chunkDelay, max(state.chunkSeconds, 0.001), state.lines, state.runError)
        }
        let readings = source.readings(from: startTime)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for reading in readings {
                        var from = reading.bookStart
                        while from < reading.bookEnd {
                            let to = min(from + step, reading.bookEnd)
                            if let delay { try await Task.sleep(for: delay) }
                            try Task.checkCancellation()
                            continuation.yield(ReadAlongChunk(
                                lines: generate(from, to),
                                covered: ReadAlongSpan(start: reading.bookStart, end: to)
                            ))
                            from = to
                            if let runError { throw runError }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    self.locked { $0.cancelledStarts.append(startTime) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func confidence(
        _ source: ReadAlongAudioSource,
        from startTime: Double,
        seconds: Double,
        locale: String
    ) async throws -> Double {
        let (score, fails) = locked { ($0.confidences[locale] ?? 0, $0.confidenceErrors.contains(locale)) }
        if fails { throw ReadAlongTranscriberError.unsupportedLocale(locale) }
        return score
    }

    // MARK: Canned text

    /// A line every 4 s of book time, "Seeded line N of the read-along text" (N counted from the
    /// book's start, so a line reads the same whichever run produced it), words 0.5 s apart.
    static func seededLines(from: Double, to: Double) -> [ReadAlongLine] {
        let interval = 4.0
        let wordSeconds = 0.5
        var index = Int((from / interval).rounded(.up))
        var result: [ReadAlongLine] = []
        while Double(index) * interval < to {
            let start = Double(index) * interval
            let texts = "Seeded line \(index + 1) of the read-along text".split(separator: " ")
            let words = texts.enumerated().map { offset, text in
                ReadAlongWord(
                    text: String(text),
                    start: start + Double(offset) * wordSeconds,
                    end: start + Double(offset + 1) * wordSeconds
                )
            }
            result.append(ReadAlongLine(start: start, end: words.last?.end ?? start, words: words))
            index += 1
        }
        return result
    }

    private func locked<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}
#endif
