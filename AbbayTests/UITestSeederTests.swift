//
//  UITestSeederTests.swift
//  AbbayTests
//

#if DEBUG
@testable import Abbay
import XCTest

/// `UITestSeeder` is the only state-injection channel the UI tests have, so a silent failure
/// there would make every UI test assert against the wrong library.
final class UITestSeederTests: XCTestCase {
    private var loadAll = MockLoadAllAudiosUseCase()
    private var save = MockSaveAudioUseCase()
    private var delete = MockDeleteAudioUseCase()

    override func setUpWithError() throws {
        try super.setUpWithError()
        loadAll = MockLoadAllAudiosUseCase()
        save = MockSaveAudioUseCase()
        delete = MockDeleteAudioUseCase()
        loadAll.stub = [AudioModel(title: "Existing", url: URL(string: "file:///existing.m4b"))]
    }

    private func run(_ arguments: [String]) {
        UITestSeeder.run(arguments: arguments, loadAll: loadAll, save: save, delete: delete)
    }

    func test_noLaunchArguments_leavesTheLibraryAlone() {
        run(["/path/to/Abbay"])

        XCTAssertTrue(delete.deletedAudios.isEmpty, "a normal launch must never touch the library")
        XCTAssertTrue(save.savedModels.isEmpty)
    }

    func test_resetArgument_clearsAndSeedsNothing() {
        run([LaunchArgument.resetLibrary])

        XCTAssertEqual(delete.deletedAudios.count, 1)
        XCTAssertEqual(delete.deletedAudios.first?.title, "Existing")
        XCTAssertTrue(save.savedModels.isEmpty)
    }

    func test_seedArgument_clearsFirstThenSeeds() {
        run([LaunchArgument.seedLibrary])

        XCTAssertEqual(
            delete.deletedAudios.count,
            1,
            "seeding must clear first, or repeated runs accumulate books"
        )
        XCTAssertEqual(save.savedModels.count, UITestSeeder.seedModels().count)
        // One call each, so seeding writes the library snapshot twice, not once a book.
        XCTAssertEqual(delete.batches.count, 1)
        XCTAssertEqual(save.batches.count, 1)
    }

    /// The mini player's last-row test needs a list longer than the screen.
    func test_fillerArgument_addsDistinctFillerBooks() {
        run([LaunchArgument.seedLibrary, LaunchArgument.seedFillerBooks])

        XCTAssertEqual(save.savedModels.count, UITestSeeder.seedModels().count + 12)
        XCTAssertEqual(Set(save.savedModels.compactMap(\.url)).count, save.savedModels.count)
    }

    /// The chapter list's collapse is checked on a list much longer than the screen.
    func test_longBookArgument_addsASixtyChapterBook() throws {
        run([LaunchArgument.seedLibrary, LaunchArgument.seedLongBook])

        XCTAssertEqual(save.savedModels.count, UITestSeeder.seedModels().count + 1)
        let long = try XCTUnwrap(save.savedModels.first { $0.title == UITestSeeder.longBookTitle })
        XCTAssertEqual(long.chapters.count, 60)
        XCTAssertEqual(long.chapters.last?.endTime, long.duration)
        XCTAssertEqual(Set(save.savedModels.compactMap(\.url)).count, save.savedModels.count)
    }

    func test_longBookArgument_withoutSeed_seedsNothing() {
        run([LaunchArgument.seedLongBook])

        XCTAssertTrue(save.savedModels.isEmpty)
    }

    func test_fillerArgument_withoutSeed_seedsNothing() {
        run([LaunchArgument.seedFillerBooks])

        XCTAssertTrue(save.savedModels.isEmpty)
        XCTAssertTrue(delete.deletedAudios.isEmpty)
    }

    /// The chapter actions' UI tests need a book that can seek: the real fixture, mid-chapter.
    func test_playableBookArgument_addsTheFixtureMidChapterTwo() throws {
        run([LaunchArgument.seedLibrary, LaunchArgument.seedPlayableBook])

        XCTAssertEqual(save.savedModels.count, UITestSeeder.seedModels().count + 1)
        let playable = try XCTUnwrap(save.savedModels.first { $0.title == UITestSeeder.playableBookTitle })
        let url = try XCTUnwrap(playable.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the fixture is not in the Debug app: \(url)")
        XCTAssertEqual(playable.currentChapter(for: playable.currentTime), 1, "the seed starts in chapter 2")
        XCTAssertGreaterThan(
            playable.currentTime,
            playable.chapters[1].startTime + 15,
            "mid-chapter, so restart moves it"
        )
    }

    /// The seeded chapters are typed in by hand: they must match what the file itself says.
    func test_playableBook_chaptersMatchTheFile() async throws {
        let playable = try XCTUnwrap(UITestSeeder.playableBookModel())
        let url = try XCTUnwrap(playable.url)
        let loader = FileLoader(loadAudioUseCase: MockLoadAudioUseCase(), saveAudioUseCase: MockSaveAudioUseCase())
        let loaded = await loader.load(url: url)
        let parsed = try XCTUnwrap(loaded, "the fixture did not load")

        XCTAssertEqual(playable.chapters.count, parsed.chapters.count)
        for (seeded, real) in zip(playable.chapters, parsed.chapters) {
            XCTAssertEqual(seeded.startTime, real.startTime, accuracy: 0.05)
            XCTAssertEqual(seeded.duration, real.duration, accuracy: 0.05)
        }
        XCTAssertEqual(playable.duration, parsed.duration, accuracy: 0.5)
    }

    func test_playableBookArgument_withoutSeed_seedsNothing() {
        run([LaunchArgument.seedPlayableBook])

        XCTAssertTrue(save.savedModels.isEmpty)
    }

    func test_seedModels_coverBothChapterStates() {
        let models = UITestSeeder.seedModels()

        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(
            models.filter { !$0.chapters.isEmpty }.count,
            1,
            "one chaptered book, so the player's chapter list is reachable"
        )
        XCTAssertEqual(
            models.filter { $0.chapters.isEmpty }.count,
            1,
            "one chapterless book, so the no-chapter row state is reachable"
        )
    }

    func test_seedModels_haveDistinctTitlesAndURLs() {
        let models = UITestSeeder.seedModels()

        XCTAssertEqual(Set(models.map(\.title)).count, models.count, "titles identify rows in UI tests")
        XCTAssertEqual(Set(models.compactMap(\.url)).count, models.count, "rows are keyed by url")
    }
}
#endif
