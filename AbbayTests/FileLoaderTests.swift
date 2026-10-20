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

    // MARK: - load(urls:)

    func test_loadUrls_prefersCachedModelAndDoesNotSaveAgain() async throws {
        let url = try fixtureURL()
        let loadAudio = MockLoadAudioUseCase()
        loadAudio.stubs[url.absoluteString] = AudioModel(title: "Cached", url: url)
        let saveAudio = MockSaveAudioUseCase()

        let files = await makeLoader(loadAudio: loadAudio, saveAudio: saveAudio)
            .load(urls: [try fixtureURL()])

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.title, "Cached", "a stored model must win over re-parsing")
        XCTAssertEqual(saveAudio.savedModels.count, 0, "nothing new was parsed, so nothing to save")
    }

    func test_loadUrls_parsesAndPersistsWhenNotCached() async throws {
        let loadAudio = MockLoadAudioUseCase()   // no stubs -> cache miss
        let saveAudio = MockSaveAudioUseCase()

        let files = await makeLoader(loadAudio: loadAudio, saveAudio: saveAudio)
            .load(urls: [try fixtureURL()])

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.chapters.count, 4)
        XCTAssertEqual(saveAudio.savedModels.count, 1, "a freshly parsed file is persisted")
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
