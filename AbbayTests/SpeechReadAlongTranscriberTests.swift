//
//  SpeechReadAlongTranscriberTests.swift
//  AbbayTests
//

@testable import Abbay
import Speech
import XCTest

/// The real on-device engine against `Fixtures/Christmastide.m4b` (public-domain LibriVox; chapter
/// 0 runs 0–144.015 s), plus the pure pieces it is built on: which files to read from a book time,
/// and moving the engine's times into book time.
///
/// The engine tests skip, rather than fail, where Speech has no transcriber or no model installed
/// (some simulators): the pure tests still pin the offset arithmetic there.
final class SpeechReadAlongTranscriberTests: XCTestCase {
    private static let chapterEnd = 144.015

    private func fixtureURL() throws -> URL {
        try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "Christmastide", withExtension: "m4b"),
            "Fixtures/Christmastide.m4b is missing from the test bundle."
        )
    }

    private func firstChapter() throws -> ReadAlongAudioSource {
        ReadAlongAudioSource(
            segments: [
                .init(fileURL: try fixtureURL(), bookStart: 0, duration: Self.chapterEnd, isSecurityScoped: false)
            ],
            isLibriVox: false
        )
    }

    /// The whole fixture as one segment: about 830 s, long enough to tell a stopped run apart.
    private func wholeFile() throws -> ReadAlongAudioSource {
        ReadAlongAudioSource(
            segments: [.init(fileURL: try fixtureURL(), bookStart: 0, duration: 831.6, isSecurityScoped: false)],
            isLibriVox: false
        )
    }

    private func segment(_ start: Double, _ duration: Double, onDevice: Bool = true) -> ReadAlongAudioSource.Segment {
        .init(
            fileURL: onDevice ? URL(fileURLWithPath: "/books/\(Int(start)).mp3") : nil,
            bookStart: start,
            duration: duration,
            isSecurityScoped: false
        )
    }

    // MARK: - Readings (pure)

    func test_readings_startMidFile_offsetsIntoThatFile_thenReadsTheNextFromItsStart() {
        let first = segment(0, 100)
        let second = segment(100, 50)
        let source = ReadAlongAudioSource(segments: [first, second], isLibriVox: true)

        let readings = source.readings(from: 30)

        XCTAssertEqual(readings, [.init(segment: first, offset: 30), .init(segment: second, offset: 0)])
        XCTAssertEqual(readings.map(\.bookStart), [30, 100])
        XCTAssertEqual(readings.map(\.bookEnd), [100, 150])
    }

    func test_readings_stopBeforeTheFirstFileNotOnDevice() {
        let first = segment(0, 100)
        let source = ReadAlongAudioSource(
            segments: [first, segment(100, 50, onDevice: false), segment(150, 50)],
            isLibriVox: true
        )

        XCTAssertEqual(source.readings(from: 10), [.init(segment: first, offset: 10)])
    }

    func test_readings_startInAFileNotOnDevice_readNothing() {
        let source = ReadAlongAudioSource(
            segments: [segment(0, 100), segment(100, 50, onDevice: false)],
            isLibriVox: true
        )

        XCTAssertEqual(source.readings(from: 120), [])
    }

    func test_readings_startPastTheEnd_readNothing() {
        let source = ReadAlongAudioSource(segments: [segment(0, 100)], isLibriVox: false)

        XCTAssertEqual(source.readings(from: 100), [])
        XCTAssertEqual(ReadAlongAudioSource(segments: [], isLibriVox: false).readings(from: 0), [])
    }

    // MARK: - Book time (pure)

    func test_shifted_movesTheLineAndItsWordsIntoBookTime() {
        // The engine times from where analysis began: 2 s into a read that started 30 s into a
        // file whose 0 s is book time 600.
        let reading = ReadAlongAudioSource.Reading(segment: segment(600, 300), offset: 30)
        let line = ReadAlongLine(start: 2, end: 3, words: [.init(text: "Merry", start: 2, end: 2.4)])

        let shifted = line.shifted(by: reading.bookStart)

        XCTAssertEqual(
            shifted,
            ReadAlongLine(start: 632, end: 633, words: [.init(text: "Merry", start: 632, end: 632.4)])
        )
    }

    func test_clipped_keepsOnlyWhatIsBeforeTheEnd() {
        let line = ReadAlongLine(start: 10, end: 14, words: [
            .init(text: "a", start: 10, end: 11),
            .init(text: "b", start: 11.5, end: 12.5),
            .init(text: "c", start: 13, end: 14)
        ])

        XCTAssertEqual(line.clipped(to: 20), line)
        XCTAssertEqual(
            line.clipped(to: 12),
            ReadAlongLine(start: 10, end: 12, words: [
                .init(text: "a", start: 10, end: 11),
                .init(text: "b", start: 11.5, end: 12)
            ])
        )
        XCTAssertNil(line.clipped(to: 10))
    }

    // MARK: - Engine (integration)

    @available(iOS 26, *)
    func test_christmastide_firstChapter_producesTimedEnglishLines() async throws {
        try XCTSkipUnless(SpeechTranscriber.isAvailable, "SpeechTranscriber unavailable here")
        let transcriber = SpeechReadAlongTranscriber()
        let status = await transcriber.modelStatus(locale: "en-US")
        try XCTSkipUnless(status == .installed, "en-US model not installed (status \(status))")

        var lines: [ReadAlongLine] = []
        var covered: [ReadAlongSpan] = []
        for try await chunk in transcriber.transcribe(try firstChapter(), from: 30, locale: "en-US") {
            lines += chunk.lines
            covered.append(chunk.covered)
        }

        XCTAssertGreaterThan(lines.count, 5)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(lines.first).start, 29.5) // started at 30 s, in book time
        // Offset added once, not twice, and the run stops at the chapter's end though the file goes
        // on: nothing ends past it.
        XCTAssertLessThanOrEqual(try XCTUnwrap(lines.last).end, Self.chapterEnd)
        XCTAssertTrue(lines.allSatisfy { $0.words.allSatisfy { $0.end >= $0.start } })
        XCTAssertTrue(lines.allSatisfy { !$0.words.isEmpty })
        XCTAssertEqual(lines.map(\.start), lines.map(\.start).sorted())
        XCTAssertEqual(covered.last, ReadAlongSpan(start: 30, end: Self.chapterEnd))
    }

    @available(iOS 26, *)
    func test_confidence_englishBeatsPortuguese_onEnglishAudio() async throws {
        try XCTSkipUnless(SpeechTranscriber.isAvailable, "SpeechTranscriber unavailable here")
        let transcriber = SpeechReadAlongTranscriber()
        for locale in ["en-US", "pt-BR"] {
            let status = await transcriber.modelStatus(locale: locale)
            try XCTSkipUnless(status == .installed, "\(locale) model not installed (status \(status))")
        }
        let source = try firstChapter()

        let english = try await transcriber.confidence(source, from: 10, seconds: 20, locale: "en-US")
        let portuguese = try await transcriber.confidence(source, from: 10, seconds: 20, locale: "pt-BR")

        XCTAssertGreaterThan(english, portuguese)
    }

    /// The consumer's iterator returns nil as soon as it is cancelled, whatever the producer does,
    /// so this watches the producer: a cancelled run must stop reading long before a full run ends.
    @available(iOS 26, *)
    func test_cancelling_stopsTheEngine_notOnlyTheStream() async throws {
        try XCTSkipUnless(SpeechTranscriber.isAvailable, "SpeechTranscriber unavailable here")
        let status = await SpeechReadAlongTranscriber().modelStatus(locale: "en-US")
        try XCTSkipUnless(status == .installed, "en-US model not installed (status \(status))")
        let source = try wholeFile()

        let fullEnded = expectation(description: "full run ended")
        let full = SpeechReadAlongTranscriber(runEnded: { fullEnded.fulfill() })
        var started = Date()
        for try await _ in full.transcribe(source, from: 0, locale: "en-US") {}
        await fulfillment(of: [fullEnded], timeout: 300)
        let fullSeconds = Date().timeIntervalSince(started)

        let cancelledEnded = expectation(description: "cancelled run ended")
        let cancelled = SpeechReadAlongTranscriber(runEnded: { cancelledEnded.fulfill() })
        started = Date()
        let run = Task {
            for try await _ in cancelled.transcribe(source, from: 0, locale: "en-US") {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        try await run.value
        await fulfillment(of: [cancelledEnded], timeout: fullSeconds)
        let cancelledSeconds = Date().timeIntervalSince(started)

        XCTAssertLessThan(cancelledSeconds, fullSeconds / 2, "full run \(fullSeconds) s")
    }
}

/// Counts calls from any thread.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

/// The stub the session and UI tests drive: it must follow the protocol's contract.
@MainActor
final class StubReadAlongTranscriberTests: XCTestCase {
    func test_transcribe_coversToTheEndOfTheFilesOnDevice_withSeededLines_andRecordsTheStart() async throws {
        let stub = StubReadAlongTranscriber()
        let source = ReadAlongAudioSource(
            segments: [
                .init(fileURL: URL(fileURLWithPath: "/a.mp3"), bookStart: 0, duration: 20, isSecurityScoped: false),
                .init(fileURL: nil, bookStart: 20, duration: 20, isSecurityScoped: false)
            ],
            isLibriVox: true
        )

        var lines: [ReadAlongLine] = []
        var covered: [ReadAlongSpan] = []
        for try await chunk in stub.transcribe(source, from: 6, locale: "en-US") {
            lines += chunk.lines
            covered.append(chunk.covered)
        }

        XCTAssertEqual(stub.transcribeStarts, [6])
        XCTAssertEqual(lines.map(\.start), [8, 12, 16])
        XCTAssertEqual(lines.first?.text, "Seeded line 3 of the read-along text")
        XCTAssertEqual(lines.first?.words.map(\.start), [8, 8.5, 9, 9.5, 10, 10.5, 11])
        XCTAssertEqual(covered.last, ReadAlongSpan(start: 6, end: 20))
    }

    func test_installModel_recordsTheCall_andInstallsTheModel() async throws {
        let stub = StubReadAlongTranscriber()
        stub.supported = ["en-US", "pt-BR"]
        stub.installed = ["en-US"]

        let before = await stub.modelStatus(locale: "pt-BR")
        try await stub.installModel(locale: "pt-BR")
        let after = await stub.modelStatus(locale: "pt-BR")
        let missing = await stub.modelStatus(locale: "fr-FR")

        XCTAssertEqual(before, .downloadable)
        XCTAssertEqual(after, .installed)
        XCTAssertEqual(missing, .unsupported)
        XCTAssertEqual(stub.installCalls, ["pt-BR"])
        let installed = await stub.installedLocales()
        XCTAssertEqual(installed, ["en-US", "pt-BR"])
    }

    /// Task 6's session tests rely on a cancelled stub run stopping, not only its stream going
    /// quiet: count the generator's calls after the cancel.
    func test_cancelling_stopsTheRun() async throws {
        let stub = StubReadAlongTranscriber()
        let calls = CallCounter()
        stub.chunkDelay = .milliseconds(20)
        stub.chunkSeconds = 4
        stub.lines = { from, to in
            calls.increment()
            return StubReadAlongTranscriber.seededLines(from: from, to: to)
        }
        let source = ReadAlongAudioSource(
            segments: [
                .init(fileURL: URL(fileURLWithPath: "/a.mp3"), bookStart: 0, duration: 1000, isSecurityScoped: false)
            ],
            isLibriVox: false
        )

        let run = Task {
            for try await _ in stub.transcribe(source, from: 0, locale: "en-US") {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        try await run.value
        try await Task.sleep(for: .milliseconds(100))
        let afterCancel = calls.value
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(calls.value, afterCancel, "the run kept generating after the cancel")
        XCTAssertLessThan(afterCancel, 5)
    }

    func test_confidence_isPerLocale() async throws {
        let stub = StubReadAlongTranscriber()
        stub.confidences = ["en-US": 0.4, "pt-BR": 0.9]
        let source = ReadAlongAudioSource(segments: [], isLibriVox: false)

        let english = try await stub.confidence(source, from: 0, seconds: 20, locale: "en-US")
        let portuguese = try await stub.confidence(source, from: 0, seconds: 20, locale: "pt-BR")

        XCTAssertEqual(english, 0.4)
        XCTAssertEqual(portuguese, 0.9)
    }
}
