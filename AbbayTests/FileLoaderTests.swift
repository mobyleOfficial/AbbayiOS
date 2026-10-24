//
//  FileLoaderTests.swift
//  AbbayTests
//

@testable import Abbay
import XCTest

/// Exercises the real parsing path against a real chaptered m4b
/// (`Fixtures/Christmastide.m4b`, public domain -- see `Fixtures/README.md`).
///
/// Assertions are structural rather than content-based: counts, boundaries and ordering, so
/// the suite does not become brittle on exact metadata strings.
final class FileLoaderTests: XCTestCase {
    /// Chapter starts in the fixture, in seconds.
    private let expectedStarts: [Double] = [0, 144.015, 288.012, 511.021]
    private let expectedDuration: Double = 831.6
    private let tolerance: Double = 0.05

    private func fixtureURL() throws -> URL {
        try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "Christmastide", withExtension: "m4b"),
            "Fixtures/Christmastide.m4b is missing from the test bundle. It is declared as a "
                + "resource in project.yml; re-run `bundle exec fastlane generate_project`."
        )
    }

    private func makeLoader(
        loadAudio: MockLoadAudioUseCase = .init(),
        saveAudio: MockSaveAudioUseCase = .init()
    ) -> FileLoader {
        FileLoader(loadAudioUseCase: loadAudio, saveAudioUseCase: saveAudio)
    }

    // MARK: - Metadata

    func test_load_readsDurationFromRealAsset() async throws {
        let model = try await XCTUnwrapAsync(await makeLoader().load(url: try fixtureURL()))

        XCTAssertEqual(model.duration, expectedDuration, accuracy: 0.5)
    }

    func test_load_readsCommonMetadata() async throws {
        let model = try await XCTUnwrapAsync(await makeLoader().load(url: try fixtureURL()))

        XCTAssertFalse(model.title.isEmpty, "title should come from the asset's common metadata")
        XCTAssertTrue(
            model.albumName.localizedCaseInsensitiveContains("christmastide"),
            "unexpected album: \(model.albumName)"
        )
        XCTAssertFalse(model.artist.isEmpty)
    }

    func test_load_setsURLAndBookmark() async throws {
        let url = try fixtureURL()
        let model = try await XCTUnwrapAsync(await makeLoader().load(url: url))

        XCTAssertEqual(model.url, url)
        XCTAssertNotNil(model.bookmarkData, "a bookmark is created while the scope is held")
    }

    // MARK: - Chapters

    /// Regression guard for the `und` chapter locale. LibriVox m4b files report an undetermined
    /// chapter locale, so plain `Locale.preferredLanguages` matching finds nothing.
    /// `loadChapterMetadata` appends the asset's own locale, which is what makes this work.
    func test_load_parsesAllChaptersDespiteUndeterminedLocale() async throws {
        let model = try await XCTUnwrapAsync(await makeLoader().load(url: try fixtureURL()))

        XCTAssertEqual(model.chapters.count, 4, "the fixture has four chapters")
    }

    func test_load_chapterStartTimesAreOrderedAndCorrect() async throws {
        let model = try await XCTUnwrapAsync(await makeLoader().load(url: try fixtureURL()))

        XCTAssertEqual(model.chapters.count, expectedStarts.count)
        for (index, expected) in expectedStarts.enumerated() {
            XCTAssertEqual(
                model.chapters[index].startTime,
                expected,
                accuracy: tolerance,
                "chapter \(index) start"
            )
        }
    }

    func test_load_chaptersAreContiguous() async throws {
        let model = try await XCTUnwrapAsync(await makeLoader().load(url: try fixtureURL()))
        let chapters = model.chapters
        try XCTSkipIf(chapters.count < 2)

        for index in 0..<(chapters.count - 1) {
            XCTAssertEqual(
                chapters[index].endTime,
                chapters[index + 1].startTime,
                accuracy: tolerance,
                "gap between chapter \(index) and \(index + 1)"
            )
        }
    }

    func test_load_everyChapterHasATitle() async throws {
        let model = try await XCTUnwrapAsync(await makeLoader().load(url: try fixtureURL()))

        for (index, chapter) in model.chapters.enumerated() {
            XCTAssertFalse(chapter.title.isEmpty, "chapter \(index) has no title")
        }
    }

    // MARK: - currentChapter against real boundaries

    func test_currentChapter_resolvesMidChapterTimes() async throws {
        let model = try await XCTUnwrapAsync(await makeLoader().load(url: try fixtureURL()))

        XCTAssertEqual(model.currentChapter(for: 10), 0)
        XCTAssertEqual(model.currentChapter(for: 200), 1)
        XCTAssertEqual(model.currentChapter(for: 400), 2)
        XCTAssertEqual(model.currentChapter(for: 600), 3)
    }

    /// The last chapter ends at 831.623 s. The old `time + 1` lookup found no chapter in the final
    /// second and fell back to chapter 0 (#101).
    func test_currentChapter_lastSecondOfTheBook_isTheLastChapter() async throws {
        let model = try await XCTUnwrapAsync(await makeLoader().load(url: try fixtureURL()))
        let end = try XCTUnwrap(model.chapters.last).endTime

        XCTAssertEqual(model.currentChapter(for: end - 0.9), 3)
        XCTAssertEqual(model.currentChapter(for: end), 3)
        XCTAssertEqual(model.currentChapter(for: model.duration + 5), 3)
    }

    func test_currentChapter_switchesExactlyAtTheRealBoundaries() async throws {
        let model = try await XCTUnwrapAsync(await makeLoader().load(url: try fixtureURL()))

        for index in 1..<model.chapters.count {
            let start = model.chapters[index].startTime
            XCTAssertEqual(model.currentChapter(for: start - 0.5), index - 1, "half a second before chapter \(index)")
            XCTAssertEqual(model.currentChapter(for: start), index, "at chapter \(index)'s start")
        }
    }

    // MARK: - load(urls:)

    func test_loadUrls_prefersCachedModelAndDoesNotSaveAgain() async throws {
        let url = try fixtureURL()
        let loadAudio = MockLoadAudioUseCase()
        loadAudio.stubs[url.absoluteString] = AudioModel(title: "Cached", url: url)
        let saveAudio = MockSaveAudioUseCase()

        let files = await makeLoader(loadAudio: loadAudio, saveAudio: saveAudio)
            .load(urls: [try fixtureURL()]).loaded

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.title, "Cached", "a stored model must win over re-parsing")
        XCTAssertEqual(saveAudio.savedModels.count, 0, "nothing new was parsed, so nothing to save")
    }

    func test_loadUrls_parsesAndPersistsWhenNotCached() async throws {
        let loadAudio = MockLoadAudioUseCase()   // no stubs -> cache miss
        let saveAudio = MockSaveAudioUseCase()

        let files = await makeLoader(loadAudio: loadAudio, saveAudio: saveAudio)
            .load(urls: [try fixtureURL()]).loaded

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.chapters.count, 4)
        XCTAssertEqual(saveAudio.savedModels.count, 1, "a freshly parsed file is persisted")
    }

    /// One import saves its new files together, so the library snapshot is written (and Siri
    /// published to) once per import, not once a file (#85).
    func test_loadUrls_savesTheNewFilesInOneBatch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appendingPathComponent("Copy.m4b")
        try FileManager.default.copyItem(at: try fixtureURL(), to: copy)
        let cached = directory.appendingPathComponent("Cached.m4b")
        let loadAudio = MockLoadAudioUseCase()
        loadAudio.stubs[cached.absoluteString] = AudioModel(title: "Cached", url: cached)
        let saveAudio = MockSaveAudioUseCase()

        let result = await makeLoader(loadAudio: loadAudio, saveAudio: saveAudio)
            .load(urls: [try fixtureURL(), cached, copy])

        XCTAssertEqual(result.loaded.count, 3)
        XCTAssertEqual(saveAudio.batches.map { $0.map(\.url) }, [[try fixtureURL(), copy]])
    }

    /// #115: a file that won't load is reported back, so the library can say which one it was.
    func test_loadUrls_reportsTheFilesThatFailedAlongsideTheLoadedOnes() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).mp3")
        let saveAudio = MockSaveAudioUseCase()

        let result = await makeLoader(saveAudio: saveAudio).load(urls: [missing, try fixtureURL()])

        XCTAssertEqual(result.loaded.count, 1)
        XCTAssertEqual(result.failed, [missing])
        XCTAssertEqual(saveAudio.savedModels.count, 1, "nothing is saved for the failed file")
    }

    /// A file that is there but isn't audio (a text file named .mp3) fails too, instead of
    /// becoming an empty, unplayable row.
    func test_loadUrls_aFileThatIsNotAudio_fails() async throws {
        let notAudio = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-audio-\(UUID().uuidString).mp3")
        try Data("not audio".utf8).write(to: notAudio)
        defer { try? FileManager.default.removeItem(at: notAudio) }
        let saveAudio = MockSaveAudioUseCase()

        let result = await makeLoader(saveAudio: saveAudio).load(urls: [notAudio])

        XCTAssertEqual(result.loaded.count, 0)
        XCTAssertEqual(result.failed, [notAudio])
        XCTAssertEqual(saveAudio.savedModels.count, 0)
    }
}

// MARK: - Helpers

/// `XCTUnwrap` is not usable directly on an `await`ed optional in all toolchains, so unwrap
/// through a plain generic helper.
private func XCTUnwrapAsync<T>(
    _ value: T?,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}
