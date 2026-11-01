//
//  DataStack.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 03/07/23.
//

import CoreData
import os

final class DataStack: ObservableObject {
    // MARK: - Properties
    private let persistentContainer: NSPersistentContainer
    private let noticeReporter: NoticeReporting

    /// A main-queue context. Touch it, or any object fetched from it, only inside `performAndWait`:
    /// AppIntents reads the library from background threads.
    var managedContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    // MARK: - Init
    /// Loads the store eagerly. `LocalStorage.persistent` is a `static let`, so this runs once
    /// even when the first callers race on several threads (a `lazy var` would not be safe).
    ///
    /// `inMemory` is for tests: a store that starts empty and is never written to disk. So is
    /// `storeURL`: an existing store file to open, which proves an older model's store migrates.
    /// The container's defaults migrate a store saved by an older model version on load
    /// (lightweight, inferred), keeping every row.
    init(
        modelName: String,
        inMemory: Bool = false,
        storeURL: URL? = nil,
        noticeReporter: NoticeReporting = NoticeCenter.shared
    ) {
        let container = NSPersistentContainer(name: modelName)
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else if let storeURL {
            container.persistentStoreDescriptions.first?.url = storeURL
        }
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        persistentContainer = container
        self.noticeReporter = noticeReporter
    }

    // MARK: - Methods
    /// Runs `block` on the context's queue and returns its result. Fetches, mapping managed objects
    /// to models (which faults relationships) and saves all belong inside it.
    ///
    /// On the main thread the block runs inline. From any other thread it waits for the main queue,
    /// so the main thread must never block waiting on a thread that calls this. Re-entrant.
    func performAndWait<T>(_ block: (NSManagedObjectContext) throws -> T) rethrows -> T {
        let context = managedContext
        return try context.performAndWait {
            try block(context)
        }
    }

    /// A failed save is reported as a notice (#115): it can mean a lost import or position.
    func saveContext() {
        performAndWait { context in
            guard context.hasChanges else { return }
            do {
                try context.save()
            } catch let error as NSError {
                Log.data.error("save failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
                noticeReporter.report(.saveFailed)
            }
        }
    }
}
