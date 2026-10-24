//
//  LibriVoxPersistenceTests.swift
//  AbbayTests
//

@testable import Abbay
import CoreData
import XCTest

final class LibriVoxPersistenceTests: XCTestCase {
    private let bookURL = URL(string: "librivox://book/alice_in_wonderland_librivox")
    private var tempDirectory: URL?

    override func tearDown() {
        removeBook()
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        super.tearDown()
    }

    func test_saveThenLoad_roundTripsLibriVoxFields() throws {
        let audio = makeBook()

        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(audio)
        let loaded = try XCTUnwrap(LoadAudioUseCase().execute(url: bookURL))

        XCTAssertEqual(loaded.librivoxID, "alice_in_wonderland_librivox")
        XCTAssertTrue(loaded.isLibriVox)
        XCTAssertTrue(loaded.allowsCellularDownload)
        XCTAssertTrue(loaded.isDownloadPaused)
        XCTAssertEqual(loaded.totalBytes, 85_000_000)
        XCTAssertEqual(loaded.chapters.count, 2)
        XCTAssertEqual(loaded.chapters.map(\.remoteURL), audio.chapters.map(\.remoteURL))
        XCTAssertEqual(loaded.chapters.map(\.expectedBytes), [40_000_000, 45_000_000])
    }

    func test_save_existingBook_leavesPauseAndCellularFlagsAlone() throws {
        var audio = makeBook()
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(audio)

        // A stale copy, like the one `Player.saveTime()` holds, must not undo a pause or a choice.
        audio.allowsCellularDownload = false
        audio.isDownloadPaused = false
        audio.currentTime = 30
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(audio)
        let loaded = try XCTUnwrap(LoadAudioUseCase().execute(url: bookURL))

        XCTAssertTrue(loaded.allowsCellularDownload)
        XCTAssertTrue(loaded.isDownloadPaused)
        XCTAssertEqual(loaded.currentTime, 30)
        XCTAssertEqual(loaded.chapters.count, 2)
    }

    func test_updateDownloadFlags_changesOnlyTheGivenFlags() throws {
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(makeBook())

        UpdateDownloadFlagsUseCase().execute(url: bookURL, isDownloadPaused: false, allowsCellularDownload: nil)
        var loaded = try XCTUnwrap(LoadAudioUseCase().execute(url: bookURL))
        XCTAssertFalse(loaded.isDownloadPaused)
        XCTAssertTrue(loaded.allowsCellularDownload)

        UpdateDownloadFlagsUseCase().execute(url: bookURL, isDownloadPaused: nil, allowsCellularDownload: false)
        loaded = try XCTUnwrap(LoadAudioUseCase().execute(url: bookURL))
        XCTAssertFalse(loaded.isDownloadPaused)
        XCTAssertFalse(loaded.allowsCellularDownload)
        XCTAssertEqual(loaded.title, "Test LibriVox")
        XCTAssertEqual(loaded.chapters.count, 2)
    }

    func test_updateDownloadFlags_unknownBook_insertsNothing() {
        UpdateDownloadFlagsUseCase().execute(url: bookURL, isDownloadPaused: true, allowsCellularDownload: true)

        XCTAssertNil(LoadAudioUseCase().execute(url: bookURL))
    }

    func test_savePlaybackPosition_updatesOnlyTheExistingBook() throws {
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(makeBook())

        SavePlaybackPositionUseCase().execute(url: bookURL, currentTime: 75, bookmarkData: Data([4, 2]))
        let loaded = try XCTUnwrap(LoadAudioUseCase().execute(url: bookURL))

        XCTAssertEqual(loaded.currentTime, 75)
        XCTAssertEqual(loaded.bookmarkData, Data([4, 2]))
        XCTAssertEqual(loaded.title, "Test LibriVox")
        XCTAssertTrue(loaded.isDownloadPaused)
        XCTAssertEqual(loaded.chapters.count, 2)
    }

    func test_savePlaybackPosition_withoutBookmark_keepsTheSavedBookmark() throws {
        var audio = makeBook()
        audio.bookmarkData = Data([9])
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(audio)

        SavePlaybackPositionUseCase().execute(url: bookURL, currentTime: 12, bookmarkData: nil)
        let loaded = try XCTUnwrap(LoadAudioUseCase().execute(url: bookURL))

        XCTAssertEqual(loaded.currentTime, 12)
        XCTAssertEqual(loaded.bookmarkData, Data([9]))
    }

    func test_savePlaybackPosition_deletedBook_insertsNothing() throws {
        let audio = makeBook()
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(audio)
        DeleteAudioUseCase(removeDownloads: { _ in }, snapshotWriter: MockLibrarySnapshotWriter()).execute(audio)

        SavePlaybackPositionUseCase().execute(url: bookURL, currentTime: 30, bookmarkData: nil)

        XCTAssertNil(LoadAudioUseCase().execute(url: bookURL))
    }

    func test_v1Store_opensWithCurrentModel_keepsBooks() throws {
        let momd = try XCTUnwrap(
            Bundle(for: AudioDataModel.self).url(forResource: "AudioDataModel", withExtension: "momd")
        )
        let v1URL = try XCTUnwrap(momd.appendingPathComponent("AudioDataModel.mom") as URL?)
        let v1Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v1URL))
        XCTAssertNil(v1Model.entitiesByName["AudioDataModel"]?.propertiesByName["librivoxID"])

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        tempDirectory = directory
        let storeURL = directory.appendingPathComponent("AudioDataModel.sqlite")

        try insertV1Book(model: v1Model, storeURL: storeURL)

        let currentModel = try XCTUnwrap(NSManagedObjectModel(contentsOf: momd))
        let container = NSPersistentContainer(name: "AudioDataModel", managedObjectModel: currentModel)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)

        let books = try container.viewContext.fetch(AudioDataModel.fetchRequest())
        XCTAssertEqual(books.count, 1)
        let book = try XCTUnwrap(books.first)
        XCTAssertEqual(book.title, "Old Book")
        XCTAssertEqual(book.currentTime, 42)
        XCTAssertEqual(book.chapters?.count, 2)
        XCTAssertNil(book.librivoxID)
        XCTAssertFalse(book.allowsCellularDownload)
        XCTAssertEqual(book.totalBytes, 0)

        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    // MARK: - Helpers

    private func makeBook() -> AudioModel {
        var audio = AudioModel()
        audio.title = "Test LibriVox"
        audio.url = bookURL
        audio.librivoxID = "alice_in_wonderland_librivox"
        audio.allowsCellularDownload = true
        audio.isDownloadPaused = true
        audio.totalBytes = 85_000_000
        audio.chapters = [
            ChapterModel(
                title: "One",
                startTime: 0,
                duration: 60,
                remoteURL: URL(string: "https://archive.org/download/x/one.mp3"),
                expectedBytes: 40_000_000
            ),
            ChapterModel(
                title: "Two",
                startTime: 60,
                duration: 90,
                remoteURL: URL(string: "https://archive.org/download/x/two.mp3"),
                expectedBytes: 45_000_000
            )
        ]
        return audio
    }

    private func removeBook() {
        let context = LocalStorage.persistent.managedContext
        let request = AudioDataModel.fetchRequest()
        request.predicate = NSPredicate(format: "url == %@", bookURL as NSURL? ?? NSNull())
        for book in (try? context.fetch(request)) ?? [] {
            for chapter in book.chapters?.array ?? [] {
                if let chapter = chapter as? NSManagedObject { context.delete(chapter) }
            }
            context.delete(book)
        }
        LocalStorage.persistent.saveContext()
    }

    private func insertV1Book(model: NSManagedObjectModel, storeURL: URL) throws {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil
        )
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        let book = NSEntityDescription.insertNewObject(forEntityName: "AudioDataModel", into: context)
        book.setValue("Old Book", forKey: "title")
        book.setValue(42.0, forKey: "currentTime")
        book.setValue(URL(string: "file:///old.m4b"), forKey: "url")
        let chapters = (0..<2).map { index -> NSManagedObject in
            let chapter = NSEntityDescription.insertNewObject(forEntityName: "ChapterDataModel", into: context)
            chapter.setValue("Chapter \(index)", forKey: "title")
            chapter.setValue(Double(index) * 10, forKey: "startTime")
            return chapter
        }
        book.setValue(NSOrderedSet(array: chapters), forKey: "chapters")
        try context.save()
        try coordinator.remove(store)
    }
}
