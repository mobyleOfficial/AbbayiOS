//
//  ReadAlongSessionTests.swift
//  AbbayTests
//

#if DEBUG
@testable import Abbay
import XCTest

/// Read-along turned off deletes every transcript, as the live effects do.
private final class ClearingEffects: SettingsEffects {
    var store: ReadAlongStore?

    func apply(skipBackward: SkipInterval, skipForward: SkipInterval) {}
    func apply(language: AppLanguage) {}
    func clearReadAlong() { store?.deleteAll() }
}

/// The read-along session's fixtures: the stub transcriber, a temporary store and audio, and
/// settings with Read-along on. No tests of its own.
@MainActor
class ReadAlongSessionTestCase: XCTestCase {
    fileprivate let bookID = "alice_in_wonderland_librivox"
    fileprivate var root = FileManager.default.temporaryDirectory
    fileprivate var storeRoot = FileManager.default.temporaryDirectory
    fileprivate var store = ReadAlongStore(root: FileManager.default.temporaryDirectory)
    fileprivate var settings = AppSettings(store: InMemoryKeyValueStore())
    fileprivate var stub = StubReadAlongTranscriber()

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        storeRoot = root.appendingPathComponent("transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = ReadAlongStore(root: storeRoot)
        let effects = ClearingEffects()
        effects.store = store
        settings = AppSettings(store: InMemoryKeyValueStore(), effects: effects)
        settings.language = .english
        settings.readAlongEnabled = true
        stub = StubReadAlongTranscriber()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    // MARK: - Helpers

    fileprivate func makeSession(saveInterval: Duration = .zero) -> ReadAlongSession {
        let root = root
        return ReadAlongSession(
            transcriber: stub,
            store: store,
            settings: settings,
            makeSource: { ReadAlongAudioSource.make(for: $0, root: root) },
            // A bilingual device, so detection has both languages to score.
            preferredLanguages: { ["en-US", "pt-BR"] },
            saveInterval: saveInterval
        )
    }

    /// One file, on the device unless `onDevice` is false.
    fileprivate func importedBook(duration: Double = 1000, onDevice: Bool = true) throws -> AudioModel {
        let url = root.appendingPathComponent("imported-\(UUID().uuidString).m4b")
        if onDevice { try Data([0]).write(to: url) }
        var book = AudioModel()
        book.url = url
        book.duration = duration
        return book
    }

    fileprivate func libriVoxBook() -> AudioModel {
        var book = AudioModel()
        book.url = URL(string: "librivox://\(bookID)")
        book.librivoxID = bookID
        book.duration = 300
        book.chapters = (0..<3).map { index in
            ChapterModel(
                title: "Chapter \(index + 1)",
                startTime: Double(index) * 100,
                duration: 100,
                remoteURL: URL(string: "https://archive.org/download/wonderland/wonderland_ch_0\(index + 1)_64kb.mp3")
            )
        }
        return book
    }

    fileprivate func download(_ chapter: ChapterModel) throws {
        let url = try XCTUnwrap(LibriVoxIdentity.localFileURL(for: chapter, bookID: bookID, root: root))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: url)
    }

    fileprivate func line(_ start: Double, _ text: String = "Saved") -> ReadAlongLine {
        ReadAlongLine(start: start, end: start + 1, words: [ReadAlongWord(text: text, start: start, end: start + 1)])
    }

    fileprivate func waitUntil(timeout: Double = 3, _ condition: () -> Bool) async {
        let attempts = Int(timeout * 100)
        for _ in 0..<attempts where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

}

/// The per-book state machine behind the player's read-along square: what it says, when it
/// transcribes, and that it never writes one book's text, or any text at all once Read-along is
/// off, where it doesn't belong.
final class ReadAlongSessionTests: ReadAlongSessionTestCase {
    // MARK: - Showing

    func test_show_uncoveredTime_preparesThenIsReadyWithLines_transcribingFromThere() async throws {
        let book = try importedBook()
        let session = makeSession()

        session.show(book, at: 100)

        XCTAssertEqual(session.state, .preparing)
        await waitUntil { session.state == .ready }
        XCTAssertEqual(session.state, .ready)
        XCTAssertEqual(stub.transcribeStarts, [100])
        XCTAssertEqual(session.language, "en-US")
        XCTAssertEqual(session.choices, ["en-US", "pt-BR"])
        let transcript = try XCTUnwrap(session.transcript)
        XCTAssertTrue(transcript.isCovered(100))
        XCTAssertNotNil(transcript.position(at: 101))
    }

    func test_show_savedTranscriptCoveringTheTime_isReady_withoutTranscribing() async throws {
        let book = try importedBook(duration: 600)
        settings.setReadAlongLanguage("en-US", for: book.url)
        var saved = ReadAlongTranscript(language: "en-US")
        saved.add([line(0), line(100), line(300)], covering: ReadAlongSpan(start: 0, end: 600))
        store.save(saved, bookURL: try XCTUnwrap(book.url))
        let session = makeSession()

        session.show(book, at: 120)
        await waitUntil { session.state == .ready }

        XCTAssertEqual(session.state, .ready)
        XCTAssertEqual(session.transcript, saved)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(stub.transcribeStarts, [])
    }

    func test_show_sameBookAtACoveredTime_restartsNothing() async throws {
        let book = try importedBook(duration: 100)
        let session = makeSession()
        session.show(book, at: 0)
        await waitUntil { session.state == .ready && session.transcript?.isCovered(99) == true }

        session.show(book, at: 50)

        XCTAssertEqual(session.state, .ready)
        XCTAssertEqual(stub.transcribeStarts, [0])
    }

    /// Review Focus 2: a seek far away restarts the run there; a small move inside what the run is
    /// about to cover starts nothing.
    func test_timeChanged_farOutsideTheRunsReach_cancelsIt_andStartsThere_butASmallMoveDoesNot() async throws {
        let book = try importedBook(duration: 5000)
        stub.chunkSeconds = 10
        stub.chunkDelay = .milliseconds(50)
        let session = makeSession()
        session.show(book, at: 100)
        await waitUntil { stub.transcribeStarts == [100] }

        session.timeChanged(103)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(stub.transcribeStarts, [100], "a small move stays with the run")

        session.timeChanged(2000)

        XCTAssertEqual(stub.transcribeStarts, [100, 2000])
        await waitUntil { stub.cancelledStarts == [100] }
        XCTAssertEqual(stub.cancelledStarts, [100], "the old run is cancelled")
        await waitUntil { session.state == .ready }
        XCTAssertEqual(session.state, .ready)
        XCTAssertEqual(session.transcript?.isCovered(2000), true)
    }

    /// Review Focus 1: switching books never lets one book's run write into the other's text.
    func test_showAnotherBook_cancelsTheFirstRun_savesItsTextUnderIt_andShowsOnlyTheSecondBooksText() async throws {
        let bookA = try importedBook(duration: 5000)
        let bookB = try importedBook(duration: 200)
        stub.chunkSeconds = 10
        stub.chunkDelay = .milliseconds(30)
        let session = makeSession(saveInterval: .seconds(60))
        session.show(bookA, at: 3000)
        await waitUntil { (session.transcript?.covered.first?.end ?? 0) >= 3030 }
        let transcriptA = try XCTUnwrap(session.transcript)

        session.show(bookB, at: 0)

        XCTAssertEqual(store.load(bookURL: try XCTUnwrap(bookA.url)), transcriptA, "A's text saved under A")
        await waitUntil { stub.cancelledStarts == [3000] }
        XCTAssertEqual(stub.cancelledStarts, [3000])
        await waitUntil { session.state == .ready }
        try await Task.sleep(for: .milliseconds(150))
        let transcriptB = try XCTUnwrap(session.transcript)
        XCTAssertFalse(transcriptB.lines.isEmpty)
        XCTAssertTrue(transcriptB.lines.allSatisfy { $0.start < 200 }, "never A's lines")
        XCTAssertTrue(transcriptB.covered.allSatisfy { $0.end <= 200 })
        XCTAssertEqual(store.load(bookURL: try XCTUnwrap(bookA.url)), transcriptA, "A's run wrote nothing after")
        XCTAssertEqual(stub.transcribeStarts, [3000, 0])
    }

    // MARK: - Overlapping runs

    /// A run never starts inside covered audio: from a covered time near the end of what is
    /// covered, it starts at that end; far from it, nothing runs yet.
    func test_show_coveredTime_runsFromTheEndOfTheCoveredSpan_onlyWhenNearIt() async throws {
        let book = try importedBook(duration: 1000)
        settings.setReadAlongLanguage("en-US", for: book.url)
        var saved = ReadAlongTranscript(language: "en-US")
        saved.add([line(10)], covering: ReadAlongSpan(start: 0, end: 400))
        store.save(saved, bookURL: try XCTUnwrap(book.url))

        let far = makeSession()
        far.show(book, at: 100)
        await waitUntil { far.state == .ready }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(stub.transcribeStarts, [], "300 s still covered ahead: nothing to do yet")
        far.stop()

        let near = makeSession()
        near.show(book, at: 380)
        await waitUntil { stub.transcribeStarts == [400] }

        XCTAssertEqual(stub.transcribeStarts, [400])
        XCTAssertEqual(near.state, .ready)
    }

    /// A run reaching audio an earlier run covered keeps the earlier lines (a run started elsewhere
    /// cuts phrases differently), and stops there.
    func test_run_enteringCoveredAudio_keepsTheOldLines_andStops() async throws {
        let book = try importedBook(duration: 1000)
        settings.setReadAlongLanguage("en-US", for: book.url)
        var saved = ReadAlongTranscript(language: "en-US")
        let oldLines = [line(201, "Old"), line(207, "Old"), line(390, "Old")]
        saved.add(oldLines, covering: ReadAlongSpan(start: 200, end: 400))
        store.save(saved, bookURL: try XCTUnwrap(book.url))
        stub.chunkSeconds = 30
        stub.chunkDelay = .milliseconds(10)
        let session = makeSession()

        session.show(book, at: 100)
        await waitUntil { session.transcript?.covered == [ReadAlongSpan(start: 100, end: 400)] }
        try await Task.sleep(for: .milliseconds(150))

        let transcript = try XCTUnwrap(session.transcript)
        XCTAssertEqual(transcript.covered, [ReadAlongSpan(start: 100, end: 400)], "the run stopped at the old text")
        XCTAssertEqual(transcript.lines.filter { $0.start >= 200 }, oldLines, "old data wins")
        XCTAssertTrue(transcript.lines.contains { $0.start == 196 }, "the new lines before it are kept")
        XCTAssertEqual(stub.transcribeStarts, [100])
        XCTAssertEqual(stub.cancelledStarts, [100])
    }

    // MARK: - Stopping and Read-along off

    /// Review Focus 4: once stopped, the run saves nothing more, so it can't bring back what the
    /// store deleted.
    func test_stop_duringASlowRun_savesNothingAfterTheStoreIsDeleted() async throws {
        let book = try importedBook(duration: 5000)
        stub.chunkSeconds = 10
        stub.chunkDelay = .milliseconds(30)
        let session = makeSession()
        session.show(book, at: 0)
        await waitUntil { (session.transcript?.covered.first?.end ?? 0) >= 20 }

        session.stop()
        store.deleteAll()
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertFalse(FileManager.default.fileExists(atPath: storeRoot.path), "no save after deleteAll")
        XCTAssertEqual(stub.cancelledStarts, [0])
    }

    /// Turning Read-along off deletes every transcript; a run in flight must neither save again nor
    /// keep running.
    func test_turningReadAlongOff_duringARun_stopsIt_andSavesNothingAfter() async throws {
        let book = try importedBook(duration: 5000)
        stub.chunkSeconds = 10
        stub.chunkDelay = .milliseconds(30)
        let session = makeSession()
        session.show(book, at: 0)
        await waitUntil { (session.transcript?.covered.first?.end ?? 0) >= 20 }

        settings.readAlongEnabled = false
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertFalse(FileManager.default.fileExists(atPath: storeRoot.path), "no save after deleteAll")
        XCTAssertEqual(stub.cancelledStarts, [0])
        XCTAssertEqual(stub.transcribeStarts, [0])
    }

    func test_show_whileReadAlongIsOff_doesNothing() async throws {
        settings.readAlongEnabled = false
        let session = makeSession()

        session.show(try importedBook(), at: 0)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(stub.transcribeStarts, [])
        XCTAssertNil(session.transcript)
    }

    // MARK: - Center

    func test_center_isAvailableOnlyWithATranscriber() async throws {
        XCTAssertTrue(ReadAlongCenter(transcriber: stub, store: store, settings: settings).isAvailable)
        let unavailable = ReadAlongCenter(transcriber: nil, store: store, settings: settings)
        XCTAssertFalse(unavailable.isAvailable)

        let session = unavailable.makeSession()
        session.show(try importedBook(), at: 0)

        XCTAssertEqual(session.state, .failed, "below iOS 26 nothing can transcribe")
        XCTAssertNil(session.transcript)
    }
}

/// The session's language and the audio it needs: which language it reads a book in, the model,
/// and what it says while the audio isn't on the device.
final class ReadAlongSessionLanguageTests: ReadAlongSessionTestCase {
    // MARK: - Language

    func test_storedLanguageCode_isResolvedToASupportedLocale_andSavedBack() async throws {
        let book = try importedBook()
        settings.setReadAlongLanguage("en", for: book.url)
        stub.supported = ["pt-BR", "en-US"]
        let session = makeSession()

        session.show(book, at: 0)
        await waitUntil { session.state == .ready }

        XCTAssertEqual(session.language, "en-US")
        XCTAssertEqual(settings.readAlongLanguage(for: book.url), "en-US")
    }

    func test_noStoredLanguage_detectsTheMostConfidentInstalledLocale_andSavesIt() async throws {
        let book = try importedBook()
        stub.installed = ["en-US", "pt-BR"]
        stub.confidences = ["en-US": 0.4, "pt-BR": 0.9]
        let session = makeSession()

        session.show(book, at: 0)
        await waitUntil { session.state == .ready }

        XCTAssertEqual(session.language, "pt-BR")
        XCTAssertEqual(session.transcript?.language, "pt-BR")
        XCTAssertEqual(settings.readAlongLanguage(for: book.url), "pt-BR")
    }

    func test_noStoredLanguage_allScoresLow_fallsBackToTheInAppLanguage() async throws {
        let book = try importedBook()
        stub.confidences = ["en-US": 0.3, "pt-BR": 0.4]
        let session = makeSession()

        session.show(book, at: 0)
        await waitUntil { session.state == .ready }

        XCTAssertEqual(session.language, "en-US")
        XCTAssertEqual(settings.readAlongLanguage(for: book.url), "en-US")
    }

    /// A locale whose scoring throws (its model isn't usable) just has no score.
    func test_detection_aLocaleThatThrows_hasNoScore() async throws {
        let book = try importedBook()
        stub.confidences = ["pt-BR": 0.8]
        stub.confidenceErrors = ["en-US"]
        let session = makeSession()

        session.show(book, at: 0)
        await waitUntil { session.state == .ready }

        XCTAssertEqual(session.language, "pt-BR")
    }

    func test_downloadableModel_isDownloadedOnce_thenReady() async throws {
        let book = try importedBook()
        settings.setReadAlongLanguage("pt-BR", for: book.url)
        stub.installed = ["en-US"]
        stub.installDelay = .milliseconds(100)
        let session = makeSession()

        session.show(book, at: 0)
        await waitUntil { session.state == .downloadingModel("pt-BR") }
        XCTAssertEqual(session.state, .downloadingModel("pt-BR"))
        await waitUntil { session.state == .ready }

        XCTAssertEqual(session.state, .ready)
        XCTAssertEqual(stub.installCalls, ["pt-BR"])
        XCTAssertEqual(stub.transcribeStarts, [0])
    }

    func test_unsupportedLanguage_saysSo_andTranscribesNothing() async throws {
        let book = try importedBook()
        settings.setReadAlongLanguage("fr-FR", for: book.url)
        let session = makeSession()

        session.show(book, at: 0)
        await waitUntil { session.state == .unsupported("fr-FR") }

        XCTAssertEqual(session.state, .unsupported("fr-FR"))
        XCTAssertEqual(session.choices, ["en-US", "pt-BR"], "the picker still offers the others")
        XCTAssertEqual(stub.transcribeStarts, [])
        XCTAssertEqual(stub.installCalls, [])
    }

    func test_setLanguage_savesIt_deletesTheTranscript_andTranscribesAgain() async throws {
        let book = try importedBook()
        let url = try XCTUnwrap(book.url)
        let session = makeSession()
        session.show(book, at: 0)
        await waitUntil { session.state == .ready }
        XCTAssertNotNil(store.load(bookURL: url))

        session.setLanguage("pt-BR")

        XCTAssertEqual(settings.readAlongLanguage(for: url), "pt-BR")
        XCTAssertNil(store.load(bookURL: url))
        XCTAssertEqual(session.language, "pt-BR")
        await waitUntil { session.state == .ready && session.transcript?.language == "pt-BR" }
        XCTAssertEqual(session.transcript?.language, "pt-BR")
        XCTAssertEqual(stub.transcribeStarts, [0, 0])
        XCTAssertEqual(store.load(bookURL: url)?.language, "pt-BR")
    }

    // MARK: - Audio not on the device

    func test_libriVoxChapterNotDownloaded_needsDownload_andTranscribesNothing() async throws {
        let book = libriVoxBook()
        settings.setReadAlongLanguage("en", for: book.url)
        let session = makeSession()

        session.show(book, at: 150)
        await waitUntil { session.state == .needsDownload }

        XCTAssertEqual(session.state, .needsDownload)
        XCTAssertEqual(stub.transcribeStarts, [])
    }

    /// Review Focus 5: the text appears by itself once the chapter is on the device.
    func test_needsDownload_thenTheChapterArrives_preparesThenIsReady() async throws {
        let book = libriVoxBook()
        settings.setReadAlongLanguage("en", for: book.url)
        let session = makeSession()
        session.show(book, at: 150)
        await waitUntil { session.state == .needsDownload }

        try download(book.chapters[1])
        session.downloadsChanged(book)

        XCTAssertEqual(session.state, .preparing)
        await waitUntil { session.state == .ready }
        XCTAssertEqual(session.state, .ready)
        XCTAssertEqual(stub.transcribeStarts, [150])
    }

    /// The run stops before a chapter that isn't here; the text stays until the shown time gets
    /// there.
    func test_runEndingAtAMissingChapter_staysReady_untilTheTimePassesTheCoveredEnd() async throws {
        let book = libriVoxBook()
        settings.setReadAlongLanguage("en-US", for: book.url)
        try download(book.chapters[0])
        let session = makeSession()
        session.show(book, at: 50)
        await waitUntil { session.transcript?.covered == [ReadAlongSpan(start: 50, end: 100)] }

        session.timeChanged(99)
        XCTAssertEqual(session.state, .ready)

        session.timeChanged(101)
        XCTAssertEqual(session.state, .needsDownload)
        XCTAssertEqual(stub.transcribeStarts, [50])
    }

    func test_importedFileMissing_saysTheFileIsMissing() async throws {
        let book = try importedBook(onDevice: false)
        let session = makeSession()

        session.show(book, at: 0)
        await waitUntil { session.state == .fileMissing }

        XCTAssertEqual(session.state, .fileMissing)
        XCTAssertEqual(stub.transcribeStarts, [])
        XCTAssertNil(settings.readAlongLanguage(for: book.url), "no detection without the audio")
    }

    func test_runFailing_saysSo() async throws {
        let book = try importedBook()
        stub.chunkSeconds = 1
        stub.runError = ReadAlongTranscriberError.unsupportedLocale("en-US")
        let session = makeSession()

        session.show(book, at: 10)
        await waitUntil { session.state == .failed }

        XCTAssertEqual(session.state, .failed)
    }
}
#endif
