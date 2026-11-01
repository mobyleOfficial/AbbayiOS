//
//  ChapterProgressPersistenceTests.swift
//  AbbayTests
//

@testable import Abbay
import CoreData
import XCTest

/// #299: each chapter's resume offset is saved with the book's position, and a store saved by an
/// older model (1, before LibriVox; 2, the shipped one) opens with the current model through the
/// app's own `DataStack`, keeping every row, with no chapter started.
final class ChapterProgressPersistenceTests: XCTestCase {
    private let bookURL = URL(string: "file:///chapter-progress-\(UUID().uuidString).m4b")
    private var tempDirectory: URL?

    override func tearDown() {
        if let bookURL {
            DeleteAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(AudioModel(url: bookURL))
        }
        if let tempDirectory { try? FileManager.default.removeItem(at: tempDirectory) }
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - Saving and reading back

    func test_savePosition_withAChapter_writesThatChaptersOffset_andTheBookTime() throws {
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(makeBook())

        SavePlaybackPositionUseCase().execute(
            url: bookURL, currentTime: 130, bookmarkData: nil, chapter: ChapterPosition(index: 1, offset: 70)
        )

        let loaded = try XCTUnwrap(LoadAudioUseCase().execute(url: bookURL))
        XCTAssertEqual(loaded.currentTime, 130)
        XCTAssertEqual(loaded.chapters.map(\.resumeOffset), [nil, 70, nil], "only the chapter given")
    }

    func test_savePosition_chapterOutOfRange_writesTheBookTimeOnly() throws {
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(makeBook())

        SavePlaybackPositionUseCase().execute(
            url: bookURL, currentTime: 20, bookmarkData: nil, chapter: ChapterPosition(index: 7, offset: 5)
        )

        let loaded = try XCTUnwrap(LoadAudioUseCase().execute(url: bookURL))
        XCTAssertEqual(loaded.currentTime, 20)
        XCTAssertEqual(loaded.chapters.map(\.resumeOffset), [nil, nil, nil])
    }

    /// The saved book is the truth, not the copy passed in: a screen's copy predates the save.
    func test_resumeTime_readsTheSavedBook_notTheStaleCopy() throws {
        let stale = makeBook()
        try SaveAudioUseCase(snapshotWriter: MockLibrarySnapshotWriter()).execute(stale)
        SavePlaybackPositionUseCase().execute(
            url: bookURL, currentTime: 150, bookmarkData: nil, chapter: ChapterPosition(index: 1, offset: 50)
        )

        let sut = LoadChapterResumeUseCase()

        XCTAssertEqual(sut.resumeTime(ofChapter: 1, in: stale), 110, "chapter two starts at 60, left 50 s in")
        XCTAssertEqual(sut.resumeTime(ofChapter: 0, in: stale), 0, "never started: from its start")
        XCTAssertNil(sut.resumeTime(ofChapter: 3, in: stale))
    }

    func test_resumeTime_unsavedBook_usesTheCopysChapter() {
        var book = makeBook()
        book.url = URL(string: "file:///never-saved-\(UUID().uuidString).m4b")
        book.chapters[2].resumeOffset = 30

        XCTAssertEqual(LoadChapterResumeUseCase().resumeTime(ofChapter: 2, in: book), 180)
    }

    // MARK: - Migration

    func test_v2Store_opensThroughDataStack_keepsEveryRow_withNoChapterStarted() throws {
        let storeURL = try makeStore(modelFile: "AudioDataModel 2.mom") { book in
            book.setValue("lv_id", forKey: "librivoxID")
            book.setValue(true, forKey: "isDownloadPaused")
            book.setValue(Int64(9000), forKey: "totalBytes")
        }

        let stack = DataStack(modelName: "AudioDataModel", storeURL: storeURL, noticeReporter: MockNoticeReporter())

        try stack.performAndWait { context in
            let book = try XCTUnwrap(try context.fetch(AudioDataModel.fetchRequest()).first)
            XCTAssertEqual(book.title, "Old Book")
            XCTAssertEqual(book.currentTime, 42)
            XCTAssertEqual(book.librivoxID, "lv_id")
            XCTAssertTrue(book.isDownloadPaused)
            XCTAssertEqual(book.totalBytes, 9000)
            let chapters = try XCTUnwrap(book.chapters?.array as? [ChapterDataModel])
            XCTAssertEqual(chapters.map(\.title), ["Chapter 0", "Chapter 1"], "kept, in order")
            XCTAssertEqual(chapters.map(\.startTime), [0, 30])
            XCTAssertEqual(chapters.map(\.resumeOffset), [nil, nil], "optional: an old chapter reads as never started")
            XCTAssertEqual(book.mapped(resolveBookmark: { _ in nil }).model.chapters.map(\.resumeTime), [0, 30])
        }
    }

    func test_v1Store_opensThroughDataStack_keepsEveryRow() throws {
        let storeURL = try makeStore(modelFile: "AudioDataModel.mom") { _ in }

        let stack = DataStack(modelName: "AudioDataModel", storeURL: storeURL, noticeReporter: MockNoticeReporter())

        try stack.performAndWait { context in
            let book = try XCTUnwrap(try context.fetch(AudioDataModel.fetchRequest()).first)
            XCTAssertEqual(book.currentTime, 42)
            let chapters = try XCTUnwrap(book.chapters?.array as? [ChapterDataModel])
            XCTAssertEqual(chapters.map(\.title), ["Chapter 0", "Chapter 1"])
            XCTAssertEqual(chapters.map(\.resumeOffset), [nil, nil])
        }
    }

    /// After the upgrade a chapter's offset is written and read back like any other field.
    func test_migratedStore_savesAChapterOffset() throws {
        let storeURL = try makeStore(modelFile: "AudioDataModel 2.mom") { _ in }
        let stack = DataStack(modelName: "AudioDataModel", storeURL: storeURL, noticeReporter: MockNoticeReporter())

        try stack.performAndWait { context in
            let book = try XCTUnwrap(try context.fetch(AudioDataModel.fetchRequest()).first)
            (book.chapters?.array.last as? ChapterDataModel)?.resumeOffset = 12.5
            try context.save()
            context.reset()
            let reread = try XCTUnwrap(try context.fetch(AudioDataModel.fetchRequest()).first)
            let chapters = try XCTUnwrap(reread.chapters?.array as? [ChapterDataModel])
            XCTAssertEqual(chapters.map(\.resumeOffset), [nil, 12.5])
        }
    }

    // MARK: - Helpers

    private func makeBook() -> AudioModel {
        AudioModel(
            title: "Chapter progress",
            duration: 300,
            chapters: [
                ChapterModel(title: "one", startTime: 0, duration: 60),
                ChapterModel(title: "two", startTime: 60, duration: 90),
                ChapterModel(title: "three", startTime: 150, duration: 150)
            ],
            url: bookURL,
            bookmarkData: Data([1])
        )
    }

    /// A store saved by an older model version: one book at 42 s with two chapters.
    private func makeStore(modelFile: String, extra: (NSManagedObject) -> Void) throws -> URL {
        let momd = try XCTUnwrap(
            Bundle(for: AudioDataModel.self).url(forResource: "AudioDataModel", withExtension: "momd")
        )
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: momd.appendingPathComponent(modelFile)))
        XCTAssertNil(
            model.entitiesByName["ChapterDataModel"]?.propertiesByName["resumeOffset"],
            "\(modelFile) predates #299"
        )

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        tempDirectory = directory
        let storeURL = directory.appendingPathComponent("AudioDataModel.sqlite")

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
        extra(book)
        let chapters = (0..<2).map { index -> NSManagedObject in
            let chapter = NSEntityDescription.insertNewObject(forEntityName: "ChapterDataModel", into: context)
            chapter.setValue("Chapter \(index)", forKey: "title")
            chapter.setValue(Double(index * 30), forKey: "startTime")
            chapter.setValue(30.0, forKey: "duration")
            return chapter
        }
        book.setValue(NSOrderedSet(array: chapters), forKey: "chapters")
        try context.save()
        try coordinator.remove(store)
        return storeURL
    }
}
