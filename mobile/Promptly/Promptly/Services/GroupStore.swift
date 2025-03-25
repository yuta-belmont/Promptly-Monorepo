import Foundation
import CoreData

//this is just group persistence. GroupPersistence keyword

@MainActor
final class GroupStore: ObservableObject {
    static let shared = GroupStore()
    
    @Published private(set) var groups: [Models.ItemGroup] = []
    @Published var lastGroupUpdateTimestamp: Date = Date()
    
    private let persistenceController = PersistenceController.shared
    
    private init() {
        loadGroups()
    }
    
    // MARK: - Persistence
    
    func loadGroups() {
        let context = persistenceController.container.viewContext
        
        let fetchRequest: NSFetchRequest<ItemGroup> = ItemGroup.fetchRequest()
        
        do {
            let coreDataGroups = try context.fetch(fetchRequest)
            self.groups = coreDataGroups.map { $0.toStruct() }
        } catch {
            print("Failed to load groups: \(error)")
        }
    }
    
    private func saveGroups() {
        // This method is now a no-op since saving is handled by the individual CRUD methods
        // We keep it for API compatibility
    }
    
    // MARK: - Group Management
    
    func createGroup(title: String, red: Double = 0, green: Double = 0, blue: Double = 0, hasColor: Bool = false) -> Models.ItemGroup {
        let context = persistenceController.container.viewContext
        
        // Create a new struct model
        let newStructGroup = Models.ItemGroup(
            title: title,
            items: [:],
            colorRed: red,
            colorGreen: green,
            colorBlue: blue,
            hasColor: hasColor
        )
        
        // Create a Core Data model
        let newGroup = ItemGroup.create(from: newStructGroup, context: context)
        
        do {
            try context.save()
            
            // Reload groups to ensure we have the latest data
            loadGroups()
            
            // Update timestamp to trigger refresh in observers
            DispatchQueue.main.async {
                self.lastGroupUpdateTimestamp = Date()
            }
            
            // Return the struct representation
            return newGroup.toStruct()
        } catch {
            print("Failed to save new group: \(error)")
            
            // Return the struct model even if saving failed
            return newStructGroup
        }
    }
    
    func deleteGroup(_ group: Models.ItemGroup) {
        let context = persistenceController.container.viewContext
        
        // Find the Core Data group
        let fetchRequest: NSFetchRequest<ItemGroup> = ItemGroup.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", group.id as CVarArg)
        
        do {
            let results = try context.fetch(fetchRequest)
            
            if let groupToDelete = results.first {
                // Remove the group from all items
                if let items = groupToDelete.checklistItem?.allObjects as? [ChecklistItem] {
                    for item in items {
                        item.itemGroup = nil
                    }
                }
                
                // Delete the group
                context.delete(groupToDelete)
                try context.save()
                
                // Reload groups
                loadGroups()
                
                // Update timestamp to trigger refresh in observers
                DispatchQueue.main.async {
                    self.lastGroupUpdateTimestamp = Date()
                }
            }
        } catch {
            print("Failed to delete group: \(error)")
        }
    }
    
    func updateGroupTitle(_ group: Models.ItemGroup, newTitle: String) {
        let context = persistenceController.container.viewContext
        
        // Find the Core Data group
        let fetchRequest: NSFetchRequest<ItemGroup> = ItemGroup.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", group.id as CVarArg)
        
        do {
            let results = try context.fetch(fetchRequest)
            
            if let groupToUpdate = results.first {
                groupToUpdate.title = newTitle
                try context.save()
                
                // Reload groups
                loadGroups()
                
                // Update timestamp to trigger refresh in observers
                DispatchQueue.main.async {
                    self.lastGroupUpdateTimestamp = Date()
                }
            }
        } catch {
            print("Failed to update group title: \(error)")
        }
    }
    
    func updateGroupColor(_ group: Models.ItemGroup, red: Double, green: Double, blue: Double) {
        let context = persistenceController.container.viewContext
        
        // Find the Core Data group
        let fetchRequest: NSFetchRequest<ItemGroup> = ItemGroup.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", group.id as CVarArg)
        
        do {
            let results = try context.fetch(fetchRequest)
            
            if let groupToUpdate = results.first {
                groupToUpdate.colorRed = red
                groupToUpdate.colorGreen = green
                groupToUpdate.colorBlue = blue
                groupToUpdate.hasColor = true
                try context.save()
                
                // Reload groups
                loadGroups()
                
                // Update timestamp to trigger refresh in observers
                DispatchQueue.main.async {
                    self.lastGroupUpdateTimestamp = Date()
                }
            }
        } catch {
            print("Failed to update group color: \(error)")
        }
    }
    
    func removeGroupColor(_ group: Models.ItemGroup) {
        let context = persistenceController.container.viewContext
        
        // Find the Core Data group
        let fetchRequest: NSFetchRequest<ItemGroup> = ItemGroup.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", group.id as CVarArg)
        
        do {
            let results = try context.fetch(fetchRequest)
            
            if let groupToUpdate = results.first {
                groupToUpdate.colorRed = 0
                groupToUpdate.colorGreen = 0
                groupToUpdate.colorBlue = 0
                groupToUpdate.hasColor = false
                try context.save()
                
                // Reload groups
                loadGroups()
                
                // Update timestamp to trigger refresh in observers
                DispatchQueue.main.async {
                    self.lastGroupUpdateTimestamp = Date()
                }
            }
        } catch {
            print("Failed to remove group color: \(error)")
        }
    }
    
    // MARK: - Item-Group Relationship Management
    
    func addItemToGroup(item: Models.ChecklistItem, groupId: UUID) {
        let context = persistenceController.container.viewContext
        
        // Remove the item from all other groups first
        removeItemFromAllGroups(itemId: item.id)
        
        // Find the Core Data group
        let groupFetchRequest: NSFetchRequest<ItemGroup> = ItemGroup.fetchRequest()
        groupFetchRequest.predicate = NSPredicate(format: "id == %@", groupId as CVarArg)
        
        // Find the Core Data item
        let itemFetchRequest: NSFetchRequest<ChecklistItem> = ChecklistItem.fetchRequest()
        itemFetchRequest.predicate = NSPredicate(format: "id == %@", item.id as CVarArg)
        
        do {
            let groupResults = try context.fetch(groupFetchRequest)
            let itemResults = try context.fetch(itemFetchRequest)
            
            if let group = groupResults.first, let cdItem = itemResults.first {
                // Update the relationship
                cdItem.itemGroup = group
                try context.save()
                
                // Update timestamp to trigger refresh in observers
                DispatchQueue.main.async {
                    self.lastGroupUpdateTimestamp = Date()
                }
            }
        } catch {
            print("DEBUG: GroupStore - Failed to add item to group: \(error)")
        }
    }
    
    // For backward compatibility
    func addItemToGroup(itemId: UUID, date: Date, groupId: UUID) {
        let context = persistenceController.container.viewContext
        
        // Remove the item from all other groups first
        removeItemFromAllGroups(itemId: itemId)
        
        // Find the Core Data group
        let groupFetchRequest: NSFetchRequest<ItemGroup> = ItemGroup.fetchRequest()
        groupFetchRequest.predicate = NSPredicate(format: "id == %@", groupId as CVarArg)
        
        // Find the Core Data item
        let itemFetchRequest: NSFetchRequest<ChecklistItem> = ChecklistItem.fetchRequest()
        itemFetchRequest.predicate = NSPredicate(format: "id == %@", itemId as CVarArg)
        
        do {
            let groupResults = try context.fetch(groupFetchRequest)
            let itemResults = try context.fetch(itemFetchRequest)
            
            if let group = groupResults.first, let cdItem = itemResults.first {
                // Update the relationship
                cdItem.itemGroup = group
                try context.save()
                
                // Update timestamp to trigger refresh in observers
                DispatchQueue.main.async {
                    self.lastGroupUpdateTimestamp = Date()
                }
            }
        } catch {
            print("Failed to add item to group: \(error)")
        }
    }
    
    func removeItemFromGroup(itemId: UUID, groupId: UUID) {
        let context = persistenceController.container.viewContext
        
        // Find the Core Data item
        let itemFetchRequest: NSFetchRequest<ChecklistItem> = ChecklistItem.fetchRequest()
        itemFetchRequest.predicate = NSPredicate(format: "id == %@ AND itemGroup.id == %@", itemId as CVarArg, groupId as CVarArg)
        
        do {
            let itemResults = try context.fetch(itemFetchRequest)
            
            if let cdItem = itemResults.first {
                // Remove the relationship
                cdItem.itemGroup = nil
                try context.save()
                
                // Update timestamp to trigger refresh in observers
                DispatchQueue.main.async {
                    self.lastGroupUpdateTimestamp = Date()
                }
            }
        } catch {
            print("Failed to remove item from group: \(error)")
        }
    }
    
    func removeItemFromAllGroups(itemId: UUID) {
        let context = persistenceController.container.viewContext
        
        // Find the Core Data item
        let itemFetchRequest: NSFetchRequest<ChecklistItem> = ChecklistItem.fetchRequest()
        itemFetchRequest.predicate = NSPredicate(format: "id == %@", itemId as CVarArg)
        
        do {
            let itemResults = try context.fetch(itemFetchRequest)
            
            if let cdItem = itemResults.first {
                // Remove the relationship
                cdItem.itemGroup = nil
                try context.save()
                
                // Update timestamp to trigger refresh in observers
                DispatchQueue.main.async {
                    self.lastGroupUpdateTimestamp = Date()
                }
            }
        } catch {
            print("Failed to remove item from all groups: \(error)")
        }
    }
    
    func clearItemsFromGroup(groupId: UUID) {
        let context = persistenceController.container.viewContext
        
        // Find the Core Data group
        let groupFetchRequest: NSFetchRequest<ItemGroup> = ItemGroup.fetchRequest()
        groupFetchRequest.predicate = NSPredicate(format: "id == %@", groupId as CVarArg)
        
        do {
            let groupResults = try context.fetch(groupFetchRequest)
            
            if let group = groupResults.first {
                // Get all items in the group
                if let items = group.checklistItem?.allObjects as? [ChecklistItem] {
                    // Remove the relationship for each item
                    for item in items {
                        item.itemGroup = nil
                    }
                }
                
                try context.save()
                
                // Update timestamp to trigger refresh in observers
                DispatchQueue.main.async {
                    self.lastGroupUpdateTimestamp = Date()
                }
            }
        } catch {
            print("Failed to clear items from group: \(error)")
        }
    }
    
    func getGroupForItem(itemId: UUID) -> Models.ItemGroup? {
        // Find the group in our cached groups
        for group in groups {
            if group.containsItem(itemId) {
                return group
            }
        }
        return nil
    }
    
    // MARK: - Utility Methods
    
    func isItemInGroup(itemId: UUID, groupId: UUID) -> Bool {
        guard let group = getGroup(by: groupId) else { return false }
        return group.containsItem(itemId)
    }
    
    func getAllItemsInGroup(groupId: UUID) -> [Models.ChecklistItem] {
        guard let group = getGroup(by: groupId) else { return [] }
        return group.getAllItems()
    }
    
    // For backward compatibility
    func getAllItemIdsInGroup(groupId: UUID) -> [UUID] {
        guard let group = getGroup(by: groupId) else { return [] }
        return group.getAllItemIds()
    }
    
    // Helper function to get a group by ID
    func getGroup(by id: UUID) -> Models.ItemGroup? {
        let group = groups.first { $0.id == id }
        return group
    }
    
    // Helper function to update an item in a group
    func updateItemInGroup(item: Models.ChecklistItem, groupId: UUID) {
        let context = persistenceController.container.viewContext
        
        // Find the Core Data group
        let groupFetchRequest: NSFetchRequest<ItemGroup> = ItemGroup.fetchRequest()
        groupFetchRequest.predicate = NSPredicate(format: "id == %@", groupId as CVarArg)
        
        // Find the Core Data item
        let itemFetchRequest: NSFetchRequest<ChecklistItem> = ChecklistItem.fetchRequest()
        itemFetchRequest.predicate = NSPredicate(format: "id == %@", item.id as CVarArg)
        
        do {
            let groupResults = try context.fetch(groupFetchRequest)
            let itemResults = try context.fetch(itemFetchRequest)
            
            if let group = groupResults.first, let cdItem = itemResults.first {
                // Update the item
                cdItem.update(from: item, context: context)
                
                // Ensure the relationship is set
                cdItem.itemGroup = group
                
                try context.save()
                
                // Update timestamp to trigger refresh in observers
                DispatchQueue.main.async {
                    self.lastGroupUpdateTimestamp = Date()
                }
            }
        } catch {
            print("Failed to update item in group: \(error)")
        }
    }
}
