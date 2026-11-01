//
//  ChapterFinderTests.swift
//  AbbayTests
//

#if DEBUG
@testable import Abbay
import XCTest

/// Records the chapters each book is given; a book listed in `missing` has no row to save to.
private final class RecordingSaveChapters: SaveChaptersUseCaseProtocol {
    var saved: [(chapters: [ChapterModel], url: URL)] = []
    var missing: Set<URL> = []

    func execute(_ chapters: [ChapterModel], bookURL url: URL) -> [ChapterModel]? {
        guard !missing.contains(url) else { return nil }
        saved.append((chapters, url))
        return chapters
    }
}

/// *Find chapters*: what the player offers it for, and what a search leaves behind when it finds
/// chapters, finds none, can't read the file, fails, is stopped, or its switch goes off.
@MainActor
final class ChapterFinderTests: XCTestCase {
    private var root = FileManager.default.temporaryDirectory
    private var settings = AppSettings(store: InMemoryKeyValueStore())
    private var stub = StubReadAlongTranscriber()
    private var saves = RecordingSaveChapters()
    private var notices = MockNoticeReporter()
    private var notificationCenter = NotificationCenter()
    private var player = CountingMockPlayer()
    private var playback: PlaybackCenter?

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        settings = AppSettings(store: InMemoryKeyValueStore())
        settings.language = .english
        settings.findChaptersEnabled = true
        stub = StubReadAlongTranscriber()
        stub.lines = { StubReadAlongTranscriber.chapterHeadingLines(from: $0, to: $1) }
        saves = RecordingSaveChapters()
        notices = MockNoticeReporter()
        notificationCenter = NotificationCenter()
        player = CountingMockPlayer()
        playback = PlaybackCenter(player: player)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    // MARK: - What is offered

    func test_offers_anImportedBookWithoutChapters_whileItsSwitchIsOn() throws {
        let sut = makeFinder()
        var book = try importedBook()

        XCTAssertTrue(sut.offers(book), "Read-along off: its own switch")

        settings.findChaptersEnabled = false
        XCTAssertFalse(sut.offers(book), "experimental, off by default")
        settings.findChaptersEnabled = true

        book.chapters = [ChapterModel(title: "One", startTime: 0, duration: 200)]
        XCTAssertFalse(sut.offers(book), "it has chapters already")

        var libriVox = try importedBook()
        libriVox.librivoxID = "emma_librivox"
        XCTAssertFalse(sut.offers(libriVox), "a LibriVox book's chapters are its files")

        XCTAssertFalse(makeFinder(hasEngine: false).offers(try importedBook()), "no engine here")
    }

    // MARK: - A search

    func test_find_savesTheChapters_marksTheBook_andHandsThemToThePlayer() async throws {
        let sut = makeFinder()
        let book = try importedBook()
        let url = try XCTUnwrap(book.url)
        player.emitPlayUrl(book)
        var posted: [ChapterModel]?
        let observer = notificationCenter.addObserver(forName: .bookChaptersDidChange, object: url, queue: nil) {
            posted = $0.userInfo?[ChapterFinder.chaptersKey] as? [ChapterModel]
        }
        defer { notificationCenter.removeObserver(observer) }

        sut.find(book)
        XCTAssertEqual(sut.progress(of: book), 0, "searching")
        await waitUntil { sut.progress(of: book) == nil }

        let chapters = try XCTUnwrap(saves.saved.last?.chapters)
        XCTAssertEqual(chapters.map(\.title), ["Chapter One", "Chapter Two", "Chapter Three"])
        XCTAssertEqual(chapters.map(\.startTime), [0, 70, 130])
        XCTAssertEqual(saves.saved.last?.url, url)
        XCTAssertTrue(settings.hasFoundChapters(for: url))
        XCTAssertEqual(posted, chapters)
        XCTAssertEqual(playback?.state.loadedBook?.chapters, chapters, "the loaded book's copy")
        XCTAssertEqual(player.replacedChapters.last?.chapters, chapters, "the player's own")
        XCTAssertTrue(notices.notices.isEmpty)
        XCTAssertEqual(stub.transcribeStarts, [0], "the whole book, once, from its start")
    }

    func test_find_reportsProgress_asTheAudioIsCovered() async throws {
        stub.chunkSeconds = 50
        stub.chunkDelay = .milliseconds(50)
        let sut = makeFinder()
        let book = try importedBook()

        sut.find(book)
        await waitUntil { (sut.progress(of: book) ?? 0) >= 0.5 }

        let progress = try XCTUnwrap(sut.progress(of: book))
        XCTAssertGreaterThanOrEqual(progress, 0.5)
        XCTAssertLessThan(progress, 1)
        await waitUntil { sut.progress(of: book) == nil }
    }

    /// Chapters show as they are heard: from the second heading on, while the rest is searched,
    /// the latest one running to the end of the book until the next is heard.
    func test_find_showsChaptersAsTheyAreFound() async throws {
        stub.chunkSeconds = 10
        stub.chunkDelay = .milliseconds(30)
        let sut = makeFinder()
        let book = try importedBook()
        let url = try XCTUnwrap(book.url)

        sut.find(book)
        await waitUntil { !saves.saved.isEmpty }

        let first = try XCTUnwrap(saves.saved.first?.chapters)
        XCTAssertEqual(first.map(\.title), ["Chapter One", "Chapter Two"])
        XCTAssertEqual(first.last?.endTime, 200, "the latest runs to the end of the book")
        XCTAssertNotNil(sut.progress(of: book), "still searching")
        XCTAssertLessThan(sut.progress(of: book) ?? 1, 1)
        XCTAssertTrue(settings.hasFoundChapters(for: url))
        XCTAssertEqual(player.replacedChapters.first?.chapters.count, 2, "the player has them already")

        await waitUntil { sut.progress(of: book) == nil }
        XCTAssertEqual(saves.saved.map(\.chapters.count), [2, 3], "one save per new chapter, none repeated")
        XCTAssertTrue(notices.notices.isEmpty)
    }

    func test_stop_afterChaptersWereShown_keepsThem() async throws {
        stub.chunkSeconds = 10
        stub.chunkDelay = .milliseconds(50)
        let sut = makeFinder()
        var book = try importedBook()
        let url = try XCTUnwrap(book.url)

        sut.find(book)
        await waitUntil { !saves.saved.isEmpty }
        sut.cancel(book)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(saves.saved.count, 1, "nothing more after the stop, nothing taken back")
        XCTAssertTrue(settings.hasFoundChapters(for: url), "they can still be removed")
        book.chapters = try XCTUnwrap(saves.saved.last?.chapters)
        XCTAssertTrue(sut.hasFoundChapters(book))
        XCTAssertTrue(notices.notices.isEmpty)
    }

    func test_find_noHeadings_saysSo_andChangesNothing() async throws {
        stub.lines = { StubReadAlongTranscriber.seededLines(from: $0, to: $1) }
        let sut = makeFinder()
        let book = try importedBook()

        sut.find(book)
        await waitUntil { sut.progress(of: book) == nil }

        XCTAssertTrue(saves.saved.isEmpty)
        XCTAssertEqual(notices.notices, [.noChaptersFound])
        XCTAssertFalse(settings.hasFoundChapters(for: book.url))
    }

    func test_find_fileNotOnTheDevice_saysItIsMissing() async throws {
        let sut = makeFinder()
        var book = try importedBook(onDevice: false)
        book.title = "Emma"

        sut.find(book)
        await waitUntil { sut.progress(of: book) == nil }

        XCTAssertEqual(notices.notices, [.fileMissing(title: "Emma")])
        XCTAssertTrue(stub.transcribeStarts.isEmpty)
    }

    func test_find_engineFails_saysSo() async throws {
        stub.runError = CocoaError(.fileReadCorruptFile)
        let sut = makeFinder()
        let book = try importedBook()

        sut.find(book)
        await waitUntil { sut.progress(of: book) == nil }

        XCTAssertEqual(notices.notices, [.chapterSearchFailed])
        XCTAssertTrue(saves.saved.isEmpty)
    }

    func test_find_unsupportedLanguage_saysItFailed() async throws {
        let sut = makeFinder()
        var book = try importedBook()
        settings.setReadAlongLanguage("fi-FI", for: book.url)
        book.title = "Kalevala"

        sut.find(book)
        await waitUntil { sut.progress(of: book) == nil }

        XCTAssertEqual(notices.notices, [.chapterSearchFailed])
        XCTAssertTrue(stub.transcribeStarts.isEmpty)
    }

    func test_find_downloadsTheModel_whenTheLanguageNeedsIt() async throws {
        stub.installed = []
        let sut = makeFinder()
        let book = try importedBook()
        settings.setReadAlongLanguage("pt-BR", for: book.url)

        sut.find(book)
        await waitUntil { sut.progress(of: book) == nil }

        XCTAssertEqual(stub.installCalls, ["pt-BR"])
        XCTAssertEqual(saves.saved.last?.chapters.count, 3)
    }

    func test_cancel_stopsTheSearch_andSavesNothing() async throws {
        stub.chunkSeconds = 10
        stub.chunkDelay = .milliseconds(50)
        let sut = makeFinder()
        let book = try importedBook()

        sut.find(book)
        await waitUntil { !stub.transcribeStarts.isEmpty }
        sut.cancel(book)

        XCTAssertNil(sut.progress(of: book))
        await waitUntil { !stub.cancelledStarts.isEmpty }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(stub.cancelledStarts, [0])
        XCTAssertTrue(saves.saved.isEmpty)
        XCTAssertTrue(notices.notices.isEmpty)
    }

    func test_switchedOff_stopsEverySearch() async throws {
        stub.chunkSeconds = 10
        stub.chunkDelay = .milliseconds(50)
        let sut = makeFinder()
        let book = try importedBook()
        // The finder starts watching the switch on its first main-actor turn.
        await Task.yield()

        sut.find(book)
        await waitUntil { !stub.transcribeStarts.isEmpty }
        settings.findChaptersEnabled = false
        await waitUntil { sut.progress(of: book) == nil }

        XCTAssertNil(sut.progress(of: book))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(saves.saved.isEmpty)
        XCTAssertTrue(notices.notices.isEmpty)
    }

    func test_find_bookDeletedMeanwhile_leavesNoMark() async throws {
        let sut = makeFinder()
        let book = try importedBook()
        let url = try XCTUnwrap(book.url)
        saves.missing = [url]

        sut.find(book)
        await waitUntil { sut.progress(of: book) == nil }

        XCTAssertFalse(settings.hasFoundChapters(for: url))
        XCTAssertTrue(notices.notices.isEmpty)
    }

    func test_find_twice_runsOneSearch() async throws {
        stub.chunkDelay = .milliseconds(20)
        let sut = makeFinder()
        let book = try importedBook()

        sut.find(book)
        sut.find(book)
        await waitUntil { sut.progress(of: book) == nil }

        XCTAssertEqual(stub.transcribeStarts, [0])
        XCTAssertEqual(saves.saved.map(\.chapters.count), [2, 3], "one search's saves, not two")
    }

    // MARK: - Removing

    func test_removeFoundChapters_clearsThem_andTheMark() async throws {
        let sut = makeFinder()
        var book = try importedBook()
        let url = try XCTUnwrap(book.url)
        sut.find(book)
        await waitUntil { sut.progress(of: book) == nil }
        book.chapters = try XCTUnwrap(saves.saved.last?.chapters)
        XCTAssertTrue(sut.hasFoundChapters(book))

        sut.removeFoundChapters(book)

        XCTAssertEqual(saves.saved.last?.chapters, [])
        XCTAssertFalse(settings.hasFoundChapters(for: url))
        XCTAssertEqual(player.replacedChapters.last?.chapters, [])
    }

    func test_removeFoundChapters_aFilesOwnChapters_areKept() throws {
        let sut = makeFinder()
        var book = try importedBook()
        book.chapters = [ChapterModel(title: "One", startTime: 0, duration: 200)]

        XCTAssertFalse(sut.hasFoundChapters(book))
        sut.removeFoundChapters(book)

        XCTAssertTrue(saves.saved.isEmpty)
    }

    func test_detectionTime_listensPastTheOpening() {
        XCTAssertEqual(ChapterFinder.detectionTime(duration: 200), 20)
        XCTAssertEqual(ChapterFinder.detectionTime(duration: 36_000), 300)
        XCTAssertEqual(ChapterFinder.detectionTime(duration: 0), 0)
    }

    // MARK: - Helpers

    private func makeFinder(hasEngine: Bool = true) -> ChapterFinder {
        let root = root
        return ChapterFinder(
            transcriber: hasEngine ? stub : nil,
            settings: settings,
            playback: playback,
            saveChapters: saves,
            notices: notices,
            notificationCenter: notificationCenter,
            makeSource: { ReadAlongAudioSource.make(for: $0, root: root) },
            preferredLanguages: { ["en-US"] }
        )
    }

    /// One 200 s file, on the device unless `onDevice` is false.
    private func importedBook(onDevice: Bool = true) throws -> AudioModel {
        let url = root.appendingPathComponent("imported-\(UUID().uuidString).mp3")
        if onDevice { try Data([0]).write(to: url) }
        var book = AudioModel()
        book.url = url
        book.duration = 200
        return book
    }

    private func waitUntil(timeout: Double = 3, _ condition: () -> Bool) async {
        let attempts = Int(timeout * 100)
        for _ in 0..<attempts where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
#endif
