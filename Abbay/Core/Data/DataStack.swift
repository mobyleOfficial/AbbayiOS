//
//  DataStack.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 03/07/23.
//

import CoreData

final class DataStack: ObservableObject {
    // MARK: - Properties
    private let persistentContainer: NSPersistentContainer

    /// A main-queue context. Touch it, or any object fetched from it, only inside `performAndWait`:
    /// AppIntents reads the library from background threads.
    var managedContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    // MARK: - Init
    /// Loads the store eagerly. `LocalStorage.persistent` is a `static let`, so this runs once
    /// even when the first callers race on several threads (a `lazy var` would not be safe).
    init(modelName: String) {
        let container = NSPersistentContainer(name: modelName)
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        persistentContainer = container
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

    func saveContext() {
        performAndWait { context in
            guard context.hasChanges else { return }
            do {
                try context.save()
            } catch let error as NSError {
                print("❌ Unresolved error \(error), \(error.userInfo)")
            }
        }
    }
}
