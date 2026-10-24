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
    }

    /// The mini player's last-row test needs a list longer than the screen.
    func test_fillerArgument_addsDistinctFillerBooks() {
        run([LaunchArgument.seedLibrary, LaunchArgument.seedFillerBooks])

        XCTAssertEqual(save.savedModels.count, UITestSeeder.seedModels().count + 12)
        XCTAssertEqual(Set(save.savedModels.compactMap(\.url)).count, save.savedModels.count)
    }

    func test_fillerArgument_withoutSeed_seedsNothing() {
        run([LaunchArgument.seedFillerBooks])

        XCTAssertTrue(save.savedModels.isEmpty)
        XCTAssertTrue(delete.deletedAudios.isEmpty)
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
