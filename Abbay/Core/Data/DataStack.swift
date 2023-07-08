//
//  DataStack.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 03/07/23.
//

import CoreData

final class DataStack: ObservableObject {
    // MARK: - Properties
    private let modelName: String

    private lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: modelName)
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        return container
    }()

    lazy var managedContext: NSManagedObjectContext = persistentContainer.viewContext

    // MARK: - Init
    init(modelName: String) {
        self.modelName = modelName
    }

    // MARK: - Methods
    func saveContext() {
        guard managedContext.hasChanges else { return }
        do {
            try managedContext.save()
        } catch let error as NSError {
            print("Unresolved error \(error), \(error.userInfo)")
        }
    }
}
