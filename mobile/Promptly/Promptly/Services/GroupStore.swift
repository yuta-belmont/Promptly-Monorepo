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
        // Schedule loading on the next main queue cycle to avoid publishing
        // during initialization
        DispatchQueue.main.async {
            self.loadGroups {
                // Initialization completed successfully
            }
        }
    }
    
    // MARK: - GroupOrder Management
    
    private func getOrCreateGroupOrder() -> GroupOrder {
        let context = persistenceController.container.viewContext
        
        // Try to fetch existing GroupOrder
        let fetchRequest: NSFetchRequest<GroupOrder> = GroupOrder.fetchRequest()
        if let existingOrder = try? context.fetch(fetchRequest).first {
            return existingOrder
        }
        
        // Create new GroupOrder if none exists
        let groupOrder = GroupOrder(context: context)
        try? context.save()
        return groupOrder
    }
    
    // MARK: - Persistence
    
    func loadGroups(completion: (() -> Void)? = nil) {
        let context = persistenceController.container.viewContext
        let groupOrder = getOrCreateGroupOrder()
        
        do {
            // Get the ordered groups from the GroupOrder
            let orderedGroups = groupOrder.orderedGroups?.array as? [ItemGroup] ?? []
            let newGroups = orderedGroups.map { $0.toStruct() }
            
            // Dispatch updates to @Published properties to the main queue
            DispatchQueue.main.async {
                self.groups = newGroups
                self.lastGroupUpdateTimestamp = Date()
                
                // Post notification about updated groups
                NotificationCenter.default.post(name: NSNotification.Name("GroupStoreUpdated"), object: nil)
                
                // Call the completion handler after the groups have been updated
                completion?()
            }
        } catch {
            print("Failed to load groups: \(error)")
            // Still call completion even if there's an error
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
    
    private func saveGroups() {
        // This method is now a no-op since saving is handled by the individual CRUD methods
        // We keep it for API compatibility
    }
    
    // MARK: - Group Management
    
    func createGroup(title: String, red: Double = 0, green: Double = 0, blue: Double = 0, hasColor: Bool = false, completion: (() -> Void)? = nil) -> Models.ItemGroup {
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
        let structRepresentation = newGroup.toStruct()
        
        // Add to the ordered set
        let groupOrder = getOrCreateGroupOrder()
        groupOrder.addToOrderedGroups(newGroup)
        
        do {
            try context.save()
            
            // Reload groups to ensure we have the latest data - but on main queue
            DispatchQueue.main.async {
                self.loadGroups {
                    self.lastGroupUpdateTimestamp = Date()
                    completion?()
                }
            }
            
            // Return the struct representation
            return structRepresentation
        } catch {
            print("Failed to save new group: \(error)")
            
            // Still call completion even if there's an error
            DispatchQueue.main.async {
                completion?()
            }
            
            // Return the struct model even if saving failed
            return newStructGroup
        }
    }
    
    // Create a group with a specific ID
    func createGroupWithID(id: UUID, title: String, red: Double = 0, green: Double = 0, blue: Double = 0, hasColor: Bool = false, completion: (() -> Void)? = nil) -> Models.ItemGroup {
        let context = persistenceController.container.viewContext
        
        // First check if a group with this ID already exists
        let fetchRequest: NSFetchRequest<ItemGroup> = ItemGroup.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let results = try context.fetch(fetchRequest)
            
            if let existingGroup = results.first {
                // Group already exists, update it if needed
                if existingGroup.title != title {
                    existingGroup.title = title
                    try context.save()
                }
                
                // Return the existing group
                let structRepresentation = existingGroup.toStruct()
                
                // Still refresh group store
                DispatchQueue.main.async {
                    self.loadGroups {
                        self.lastGroupUpdateTimestamp = Date()
                        completion?()
                    }
                }
                
                return structRepresentation
            }
        } catch {
            print("Error checking for existing group: \(error)")
        }
        
        // Create a new struct model with the specific ID
        let newStructGroup = Models.ItemGroup(
            id: id,
            title: title,
            items: [:],
            colorRed: red,
            colorGreen: green,
            colorBlue: blue,
            hasColor: hasColor
        )
        
        // Create a Core Data model from the struct
        let newGroup = ItemGroup.create(from: newStructGroup, context: context)
        let structRepresentation = newGroup.toStruct()
        
        do {
            try context.save()
            
            // Reload groups to ensure we have the latest data
            DispatchQueue.main.async {
                self.loadGroups {
                    self.lastGroupUpdateTimestamp = Date()
                    completion?()
                }
            }
            
            // Return the struct representation
            return structRepresentation
        } catch {
            print("Failed to save new group with specific ID: \(error)")
            
            // Still call completion even if there's an error
            DispatchQueue.main.async {
                completion?()
            }
            
            // Return the struct model even if saving failed
            return newStructGroup
        }
    }
    
    func deleteGroup(_ group: Models.ItemGroup, completion: (() -> Void)? = nil) {
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
                
                // Remove from the ordered set
                if let groupOrder = groupToDelete.groupOrder {
                    groupOrder.removeFromOrderedGroups(groupToDelete)
                }
                
                // Delete the group
                context.delete(groupToDelete)
                try context.save()
                
                // Reload groups and update timestamp on main queue
                DispatchQueue.main.async {
                    self.loadGroups {
                        self.lastGroupUpdateTimestamp = Date()
                        completion?()
                    }
                }
            } else {
                // Group not found, still call completion
                DispatchQueue.main.async {
                    completion?()
                }
            }
        } catch {
            print("Failed to delete group: \(error)")
            // Call completion even on error
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
    
    func updateGroupTitle(_ group: Models.ItemGroup, newTitle: String, completion: (() -> Void)? = nil) {
        let context = persistenceController.container.viewContext
        
        // Find the Core Data group
        let fetchRequest: NSFetchRequest<ItemGroup> = ItemGroup.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", group.id as CVarArg)
        
        do {
            let results = try context.fetch(fetchRequest)
            
            if let groupToUpdate = results.first {
                groupToUpdate.title = newTitle
                try context.save()
                
                // Reload groups and update timestamp on main queue
                DispatchQueue.main.async {
                    self.loadGroups {
                        self.lastGroupUpdateTimestamp = Date()
                        completion?()
                    }
                }
            } else {
                // Group not found, still call completion
                DispatchQueue.main.async {
                    completion?()
                }
            }
        } catch {
            print("Failed to update group title: \(error)")
            // Call completion even on error
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
    
    func updateGroupColor(_ group: Models.ItemGroup, red: Double, green: Double, blue: Double, completion: (() -> Void)? = nil) {
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
                
                // Reload groups and update timestamp on main queue
                DispatchQueue.main.async {
                    self.loadGroups {
                        self.lastGroupUpdateTimestamp = Date()
                        completion?()
                    }
                }
            } else {
                // Group not found, still call completion
                DispatchQueue.main.async {
                    completion?()
                }
            }
        } catch {
            print("Failed to update group color: \(error)")
            // Call completion even on error
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
    
    func removeGroupColor(_ group: Models.ItemGroup, completion: (() -> Void)? = nil) {
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
                
                // Reload groups and update timestamp on main queue
                DispatchQueue.main.async {
                    self.loadGroups {
                        self.lastGroupUpdateTimestamp = Date()
                        completion?()
                    }
                }
            } else {
                // Group not found, still call completion
                DispatchQueue.main.async {
                    completion?()
                }
            }
        } catch {
            print("Failed to remove group color: \(error)")
            // Call completion even on error
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
    
    // MARK: - Item-Group Relationship Management
    
    func addItemToGroup(item: Models.ChecklistItem, groupId: UUID, completion: (() -> Void)? = nil) {
        let context = persistenceController.container.viewContext
        
        // Remove the item from all other groups first
        removeItemFromAllGroups(itemId: item.id) { 
            // Continue adding item to group after it's been removed from others
            let context = self.persistenceController.container.viewContext
            
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
                    
                    // Reload groups and update timestamp on main queue
                    DispatchQueue.main.async {
                        self.loadGroups {
                            self.lastGroupUpdateTimestamp = Date()
                            completion?()
                        }
                    }
                } else {
                    // Group or item not found, still call completion
                    DispatchQueue.main.async {
                        completion?()
                    }
                }
            } catch {
                print("DEBUG: GroupStore - Failed to add item to group: \(error)")
                // Call completion even on error
                DispatchQueue.main.async {
                    completion?()
                }
            }
        }
    }
    
    // For backward compatibility
    func addItemToGroup(itemId: UUID, date: Date, groupId: UUID, completion: (() -> Void)? = nil) {
        let context = persistenceController.container.viewContext
        
        // Remove the item from all other groups first
        removeItemFromAllGroups(itemId: itemId) {
            // Continue adding item to group after it's been removed from others
            let context = self.persistenceController.container.viewContext
            
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
                    
                    // Reload groups and update timestamp on main queue
                    DispatchQueue.main.async {
                        self.loadGroups {
                            self.lastGroupUpdateTimestamp = Date()
                            completion?()
                        }
                    }
                } else {
                    // Group or item not found, still call completion
                    DispatchQueue.main.async {
                        completion?()
                    }
                }
            } catch {
                print("Failed to add item to group: \(error)")
                // Call completion even on error
                DispatchQueue.main.async {
                    completion?()
                }
            }
        }
    }
    
    func removeItemFromGroup(itemId: UUID, groupId: UUID, completion: (() -> Void)? = nil) {
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
                
                // Reload groups and update timestamp on main queue
                DispatchQueue.main.async {
                    self.loadGroups {
                        self.lastGroupUpdateTimestamp = Date()
                        completion?()
                    }
                }
            } else {
                // Item not found in group, still call completion
                DispatchQueue.main.async {
                    completion?()
                }
            }
        } catch {
            print("Failed to remove item from group: \(error)")
            // Call completion even on error
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
    
    func removeItemFromAllGroups(itemId: UUID, completion: (() -> Void)? = nil) {
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
                
                // Reload groups and update timestamp on main queue
                DispatchQueue.main.async {
                    self.loadGroups {
                        self.lastGroupUpdateTimestamp = Date()
                        completion?()
                    }
                }
            } else {
                // Item not found, still call completion
                DispatchQueue.main.async {
                    completion?()
                }
            }
        } catch {
            print("Failed to remove item from all groups: \(error)")
            // Call completion even on error
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
    
    func clearItemsFromGroup(groupId: UUID, completion: (() -> Void)? = nil) {
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
                
                // Reload groups and update timestamp on main queue
                DispatchQueue.main.async {
                    self.loadGroups {
                        self.lastGroupUpdateTimestamp = Date()
                        completion?()
                    }
                }
            } else {
                // Group not found, still call completion
                DispatchQueue.main.async {
                    completion?()
                }
            }
        } catch {
            print("Failed to clear items from group: \(error)")
            // Call completion even on error
            DispatchQueue.main.async {
                completion?()
            }
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
    func updateItemInGroup(item: Models.ChecklistItem, groupId: UUID, completion: (() -> Void)? = nil) {
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
                
                // Reload groups and update timestamp on main queue
                DispatchQueue.main.async {
                    self.loadGroups {
                        self.lastGroupUpdateTimestamp = Date()
                        completion?()
                    }
                }
            } else {
                // Group or item not found, still call completion
                DispatchQueue.main.async {
                    completion?()
                }
            }
        } catch {
            print("Failed to update item in group: \(error)")
            // Call completion even on error
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
    
    func reorderGroups(from sourceIndex: Int, to destinationIndex: Int, completion: (() -> Void)? = nil) {
        let context = persistenceController.container.viewContext
        let groupOrder = getOrCreateGroupOrder()
        
        guard let orderedGroups = groupOrder.orderedGroups?.array as? [ItemGroup],
              sourceIndex >= 0 && sourceIndex < orderedGroups.count,
              destinationIndex >= 0 && destinationIndex < orderedGroups.count else {
            DispatchQueue.main.async {
                completion?()
            }
            return
        }
        
        do {
            // Get the group to move
            let groupToMove = orderedGroups[sourceIndex]
            
            // Remove it from its current position
            groupOrder.removeFromOrderedGroups(at: sourceIndex)
            
            // Insert it at the new position
            groupOrder.insertIntoOrderedGroups(groupToMove, at: destinationIndex)
            
            try context.save()
            
            // Reload groups to update the UI
            DispatchQueue.main.async {
                self.loadGroups {
                    self.lastGroupUpdateTimestamp = Date()
                    completion?()
                }
            }
        } catch {
            print("Failed to reorder groups: \(error)")
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
}
