import Foundation
import CoreData

@MainActor
final class ChecklistPersistence {
    static let shared = ChecklistPersistence()
    
    private let persistenceController = PersistenceController.shared
    
    private init() {}
    
    // MARK: - Checklist Operations
    
    func loadChecklist(for date: Date) -> Models.Checklist? {
        let context = persistenceController.container.viewContext
        
        // Create a predicate to find a checklist for this date
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate)
        
        let fetchRequest: NSFetchRequest<Checklist> = Checklist.fetchRequest()
        fetchRequest.predicate = predicate
        
        do {
            let results = try context.fetch(fetchRequest)
            
            if let coreDataChecklist = results.first {
                // Convert Core Data object to struct
                return coreDataChecklist.toStruct()
            } else {
                // No checklist found for this date
                return nil
            }
        } catch {
            print("Error loading checklist: \(error)")
            return nil
        }
    }
    
    func saveChecklist(_ checklist: Models.Checklist) {
        let context = persistenceController.container.viewContext
        
        // Check if a checklist already exists for this date
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: checklist.date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate)
        
        let fetchRequest: NSFetchRequest<Checklist> = Checklist.fetchRequest()
        fetchRequest.predicate = predicate
        
        do {
            let results = try context.fetch(fetchRequest)
            
            let coreDataChecklist: Checklist
            
            if let existingChecklist = results.first {
                // Update existing checklist
                coreDataChecklist = existingChecklist
                coreDataChecklist.update(from: checklist, context: context)
            } else {
                // Create new checklist
                coreDataChecklist = Checklist.create(from: checklist, context: context)
            }
            
            // Handle items
            updateChecklistItems(coreDataChecklist, with: checklist.items, in: context)
            
            // Save context
            try context.save()
        } catch {
            print("Error saving checklist: \(error)")
        }
    }
    
    private func updateChecklistItems(_ coreDataChecklist: Checklist, with items: [Models.ChecklistItem], in context: NSManagedObjectContext) {
        // Get existing items
        let existingItems = coreDataChecklist.checklistItem?.allObjects as? [ChecklistItem] ?? []
        
        // Create a dictionary of existing items by ID for quick lookup
        var existingItemsById: [UUID: ChecklistItem] = [:]
        for item in existingItems {
            if let id = item.id {
                existingItemsById[id] = item
            }
        }
        
        // Get the mutable ordered set for the relationship to properly maintain order
        let orderedItems = coreDataChecklist.mutableOrderedSetValue(forKey: "checklistItem")
        
        // Clear the ordered set to rebuild it with the correct order
        orderedItems.removeAllObjects()
        
        // Process each item in the struct in the order they appear in the array
        for structItem in items {
            let coreDataItem: ChecklistItem
            
            if let existingItem = existingItemsById[structItem.id] {
                // Update existing item
                coreDataItem = existingItem
                coreDataItem.update(from: structItem, context: context)
                
                // Sync subitems
                coreDataItem.syncSubItems(from: structItem, context: context)
                
                // Update group relationship if needed
                if let structGroup = structItem.group {
                    // Find or create the group
                    let group = findOrCreateGroup(from: structGroup, in: context)
                    coreDataItem.itemGroup = group
                } else {
                    coreDataItem.itemGroup = nil
                }
                
                // Remove from dictionary to track which items were processed
                existingItemsById.removeValue(forKey: structItem.id)
            } else {
                // Create new item
                coreDataItem = ChecklistItem.create(from: structItem, context: context)
                
                // Set relationships
                coreDataItem.checklist = coreDataChecklist
                
                // Set group relationship if needed
                if let structGroup = structItem.group {
                    // Find or create the group
                    let group = findOrCreateGroup(from: structGroup, in: context)
                    coreDataItem.itemGroup = group
                }
            }
            
            // Add the item to the ordered set in the correct order
            orderedItems.add(coreDataItem)
        }
        
        // Delete items that are no longer in the struct
        for (_, itemToDelete) in existingItemsById {
            context.delete(itemToDelete)
        }
    }
    
    // MARK: - Group Operations
    
    private func findOrCreateGroup(from structGroup: Models.ItemGroup, in context: NSManagedObjectContext) -> ItemGroup {
        // Try to find existing group
        let fetchRequest: NSFetchRequest<ItemGroup> = ItemGroup.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", structGroup.id as CVarArg)
        
        do {
            let results = try context.fetch(fetchRequest)
            
            if let existingGroup = results.first {
                // Update existing group
                existingGroup.update(from: structGroup, context: context)
                return existingGroup
            } else {
                // Create new group
                let newGroup = ItemGroup.create(from: structGroup, context: context)
                return newGroup
            }
        } catch {
            print("Error finding/creating group: \(error)")
            
            // Create new group as fallback
            let newGroup = ItemGroup.create(from: structGroup, context: context)
            return newGroup
        }
    }
    
    // MARK: - Delete Operations
    
    func deleteChecklist(for date: Date) {
        let context = persistenceController.container.viewContext
        
        // Create a predicate to find a checklist for this date
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate)
        
        let fetchRequest: NSFetchRequest<Checklist> = Checklist.fetchRequest()
        fetchRequest.predicate = predicate
        
        do {
            let results = try context.fetch(fetchRequest)
            
            for checklist in results {
                context.delete(checklist)
            }
            
            try context.save()
        } catch {
            print("Error deleting checklist: \(error)")
        }
    }
} 
