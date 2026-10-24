//
//  DataStackTests.swift
//  AbbayTests
//

@testable import Abbay
import CoreData
import XCTest

/// #115: a failed save used to be a `print`, so a lost import or position went unnoticed.
final class DataStackTests: XCTestCase {
    private let entity = "ChapterDataModel"
    private let key = "duration"

    /// A real save failure: another context changes the same object first, so the main context's
    /// save is a merge conflict (its merge policy is the default, error).
    func test_saveContext_whenTheSaveFails_reportsSaveFailed() throws {
        let notices = MockNoticeReporter()
        let stack = DataStack(modelName: "AudioDataModel", inMemory: true, noticeReporter: notices)
        let object = try stack.performAndWait { context in
            let object = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
            object.setValue(1.0, forKey: key)
            try context.save()
            return object
        }
        let other = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        other.persistentStoreCoordinator = stack.managedContext.persistentStoreCoordinator
        try other.performAndWait {
            other.object(with: object.objectID).setValue(2.0, forKey: key)
            try other.save()
        }
        stack.performAndWait { _ in object.setValue(3.0, forKey: key) }

        stack.saveContext()

        XCTAssertEqual(notices.notices, [.saveFailed])
    }

    func test_saveContext_whenTheSaveSucceeds_reportsNothing() {
        let notices = MockNoticeReporter()
        let stack = DataStack(modelName: "AudioDataModel", inMemory: true, noticeReporter: notices)
        stack.performAndWait { context in
            _ = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
        }

        stack.saveContext()

        XCTAssertEqual(notices.notices, [])
    }
}
