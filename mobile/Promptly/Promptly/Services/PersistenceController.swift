//
//  PersistenceController.swift
//  Promptly
//
//  Created by Yuta Belmont on 3/11/25.
//

import CoreData
import Foundation

struct PersistenceController {
    // Use a lazy static property to ensure complete initialization before access
    static let shared: PersistenceController = {
        let controller = PersistenceController()
        // Force the Core Data stack to initialize completely
        _ = controller.container.viewContext
        return controller
    }()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "DataModel")
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Error loading Core Data stores: \(error.localizedDescription)")
            }
        }
        
        // Enable automatic merging of changes from parent contexts
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Register entity descriptions
        registerEntityDescriptions()
    }
    
    // This is the critical addition - explicitly register entity descriptions
    private func registerEntityDescriptions() {
        let context = container.viewContext
        let model = container.managedObjectModel
        
        // Force the model to load all entity descriptions
        for entity in model.entities {
            if let entityName = entity.name {
                _ = NSEntityDescription.entity(forEntityName: entityName, in: context)
            }
        }
    }
    
    // Helper method to save the context if there are changes
    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    // Helper method to create a background context for operations
    func backgroundContext() -> NSManagedObjectContext {
        return container.newBackgroundContext()
    }
}
