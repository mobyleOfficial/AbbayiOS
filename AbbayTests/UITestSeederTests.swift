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
    private var lastPlayed = LastPlayedStore(store: InMemoryKeyValueStore(), legacyStore: InMemoryKeyValueStore())

    override func setUpWithError() throws {
        try super.setUpWithError()
        loadAll = MockLoadAllAudiosUseCase()
        save = MockSaveAudioUseCase()
        delete = MockDeleteAudioUseCase()
        lastPlayed = LastPlayedStore(store: InMemoryKeyValueStore(), legacyStore: InMemoryKeyValueStore())
        loadAll.stub = [AudioModel(title: "Existing", url: URL(string: "file:///existing.m4b"))]
    }

    private func run(_ arguments: [String]) {
        // Placeholder audio: the live default links the fixture into the host app's container.
        UITestSeeder.run(
            arguments: arguments,
            loadAll: loadAll,
            save: save,
            delete: delete,
            lastPlayed: lastPlayed,
            audio: UITestSeeder.placeholderAudio
        )
    }

    func test_noLaunchArguments_leavesTheLibraryAlone() {
        run(["/path/to/Abbay"])

        XCTAssertTrue(delete.deletedAudios.isEmpty, "a normal launch must never touch the library")
        XCTAssertTrue(save.savedModels.isEmpty)
    }

    /// A Continue card left from an earlier launch would move the library's grid.
    func test_seeding_clearsLastPlayed() {
        lastPlayed.save(url: URL(string: "file:///earlier.m4b"))

        run([LaunchArgument.seedLibrary])

        XCTAssertNil(lastPlayed.lastPlayedURL())
    }

    func test_seedLastPlayed_makesTheFirstSeedLastPlayed_partway() throws {
        run([LaunchArgument.seedLibrary, LaunchArgument.seedLastPlayed])

        let first = try XCTUnwrap(save.savedModels.first)
        XCTAssertEqual(lastPlayed.lastPlayedURL(), first.url)
        XCTAssertEqual(first.currentTime, UITestSeeder.lastPlayedPosition)
    }

    /// Covers on some seeds and none on *Seeded Plain Book*, so both kinds of cell show.
    func test_seedArtwork_givesSomeSeedsADecodableCover() throws {
        run([LaunchArgument.seedLibrary, LaunchArgument.seedArtwork])

        let chaptered = try XCTUnwrap(save.savedModels.first { $0.title == "Seeded Chaptered Book" })
        XCTAssertNotNil(UIImage(data: try XCTUnwrap(chaptered.imageData)))
        XCTAssertNil(save.savedModels.first { $0.title == "Seeded Plain Book" }?.imageData)
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

    /// #152's edge cases: nothing left in a book, and exactly one hour left in a chapter.
    func test_timeLeftEdgesArgument_addsAFinishedBookAndAnHourChapter() throws {
        run([LaunchArgument.seedLibrary, LaunchArgument.seedTimeLeftEdges])

        XCTAssertEqual(save.savedModels.count, UITestSeeder.seedModels().count + 2)
        let finished = try XCTUnwrap(save.savedModels.first { $0.title == UITestSeeder.finishedBookTitle })
        XCTAssertTrue(finished.chapters.isEmpty)
        XCTAssertEqual(finished.currentTime, finished.duration)
        let hour = try XCTUnwrap(save.savedModels.first { $0.title == UITestSeeder.hourBookTitle })
        XCTAssertEqual(hour.chapters.first?.duration, 3600)
        XCTAssertEqual(hour.currentTime, 0)
        XCTAssertEqual(Set(save.savedModels.compactMap(\.url)).count, save.savedModels.count)
    }

    func test_timeLeftEdgesArgument_withoutSeed_seedsNothing() {
        run([LaunchArgument.seedTimeLeftEdges])

        XCTAssertTrue(save.savedModels.isEmpty)
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

    // MARK: - Audio (#147)

    /// The moved-file banner's UI test needs a book whose file isn't there.
    func test_missingFileArgument_addsABookWithNoFile() throws {
        run([LaunchArgument.seedLibrary, LaunchArgument.seedMissingFile])

        XCTAssertEqual(save.savedModels.count, UITestSeeder.seedModels().count + 1)
        let missing = try XCTUnwrap(save.savedModels.first { $0.title == UITestSeeder.missingFileBookTitle })
        let url = try XCTUnwrap(missing.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func test_missingFileArgument_withoutSeed_seedsNothing() {
        run([LaunchArgument.seedMissingFile])

        XCTAssertTrue(save.savedModels.isEmpty)
    }

    /// The regular seeds take their audio from the seeder's source, one file per book (rows are
    /// keyed by URL).
    func test_seeds_useTheAudioSource_oneFilePerBook() {
        var names: [String] = []
        let audio: (String) -> URL = { name in
            names.append(name)
            return URL(fileURLWithPath: "/linked/\(name)")
        }

        let models = UITestSeeder.seedModels(audio: audio)
            + UITestSeeder.fillerModels(audio: audio)
            + [UITestSeeder.longBookModel(audio: audio)]

        XCTAssertEqual(Set(names).count, models.count)
        XCTAssertTrue(models.allSatisfy { $0.url?.path.hasPrefix("/linked/") == true })
    }

    /// The live source: the Debug app's fixture, linked under each seed's own name, so every
    /// regular seed plays real audio and the fixture is stored once.
    func test_linkedFixture_givesEachNameAPlayableFile() throws {
        let fixture = try TestFixtures.christmastideURL()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UITestSeederTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = UITestSeeder.linkedFixture(in: directory, fixture: fixture)

        let first = audio("chaptered.m4b")
        let second = audio("plain.m4b")
        let again = audio("chaptered.m4b")

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, again)
        let size = try XCTUnwrap(try fixture.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        for url in [first, second] {
            XCTAssertEqual(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size, "\(url)")
        }
    }

    func test_linkedFixture_withoutAFixture_fallsBackToPlaceholders() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("unused-\(UUID().uuidString)")

        let url = UITestSeeder.linkedFixture(in: directory, fixture: nil)("plain.m4b")

        XCTAssertEqual(url, UITestSeeder.placeholderAudio("plain.m4b"))
    }
}
#endif
