import Foundation
import SwiftUI

@MainActor
final class EasyListViewModel: ObservableObject {
    @Published private(set) var date: Date
    @Published var checklist: Models.Checklist
    @Published var isShowingNotes: Bool
    @Published var showingImportLimitAlert = false
    private let persistence = ChecklistPersistence.shared
    private let notificationManager = NotificationManager.shared
    private let groupStore = GroupStore.shared
    
    // Maximum number of items allowed per day
    private let maxItemsPerDay = 99
    
    // Check if the item limit is reached
    var isItemLimitReached: Bool {
        return checklist.items.count >= maxItemsPerDay
    }
    
    init(date: Date = Date()) {
        self.date = date
        self.checklist = persistence.loadChecklist(for: date) ?? Models.Checklist(date: date)
        self.isShowingNotes = UserDefaults.standard.bool(forKey: "isShowingNotes")
        
        // Clean up any empty items on load
        let emptyIndices = checklist.items.enumerated().filter { $0.element.title.isEmpty }.map { $0.offset }
        if !emptyIndices.isEmpty {
            deleteItems(at: IndexSet(emptyIndices))
        }
    }
    
    // MARK: - Date Formatting
    
    /// Formats a date relative to today (e.g., "Today", "Yesterday", "2 days ago")
    func formatRelativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let today = Date()
        
        if calendar.isDateInToday(date) {
            return "Today"
        }
        
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        }
        
        let components = calendar.dateComponents([.day], from: today, to: date)
        if let days = components.day {
            if days > 0 {
                // Add 1 to the days count for future dates
                return "\(days + 1) days from now"
            } else {
                return "\(-days) days ago"
            }
        }
        
        // Fallback to date formatting if something goes wrong
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    var headerTitle: String {
        return formatRelativeDate(date)
    }
    
    var items: [Models.ChecklistItem] {
        checklist.items
    }
    
    // MARK: - Item Management
    
    /// Helper function to update an item, handle notifications, and save the checklist
    private func updateItemAndSave(_ item: Models.ChecklistItem) {
        checklist.updateItem(item)
        notificationManager.updateNotificationForEditedItem(item, in: checklist)
        saveChecklist()
    }
    
    func updateItem(_ item: Models.ChecklistItem, with newTitle: String) {
        var updatedItem = item
        updatedItem.title = newTitle
        updateItemAndSave(updatedItem)
    }
    
    func updateItemNotification(_ item: Models.ChecklistItem, with notification: Date?) {
        var updatedItem = item
        updatedItem.notification = notification
        // Reset completion status if a notification is being set
        if notification != nil {
            updatedItem.isCompleted = false
        }
        updateItemAndSave(updatedItem)
    }
    
    func toggleItem(_ item: Models.ChecklistItem) {
        var toggledItem = item
        toggledItem.isCompleted.toggle()
        updateItemAndSave(toggledItem)
    }
    
    func deleteItems(at indexSet: IndexSet) {
        // Process items before deleting them
        for index in indexSet {
            if index < checklist.items.count {
                let item = checklist.items[index]
                // Remove from any groups and remove notifications in one pass
                cleanupItemReferences(item)
            }
        }
        
        var updatedChecklist = checklist
        updatedChecklist.deleteItems(at: indexSet)
        checklist = updatedChecklist
        saveChecklist()
    }
    
    func deleteAllItems() {
        // Process all items before deleting them
        for item in checklist.items {
            cleanupItemReferences(item)
        }
        
        var updatedChecklist = checklist
        updatedChecklist.removeAllItems()
        checklist = updatedChecklist
        saveChecklist()
    }
    
    func deleteCompletedItems() {
        // Get indices of completed items
        let completedIndices = checklist.items.enumerated()
            .filter { $0.element.isCompleted }
            .map { $0.offset }
        
        if !completedIndices.isEmpty {
            deleteItems(at: IndexSet(completedIndices))
        }
    }
    
    func deleteIncompleteItems() {
        // Get indices of incomplete items
        let incompleteIndices = checklist.items.enumerated()
            .filter { !$0.element.isCompleted }
            .map { $0.offset }
        
        if !incompleteIndices.isEmpty {
            deleteItems(at: IndexSet(incompleteIndices))
        }
    }
    
    /// Helper function to clean up all references to an item (groups and notifications)
    private func cleanupItemReferences(_ item: Models.ChecklistItem) {
        // Remove from any groups
        groupStore.removeItemFromAllGroups(itemId: item.id)
        // Remove notifications
        notificationManager.removeAllNotificationsForItem(item)
    }
    
    func addItem(_ title: String) {
        // Check if we've reached the maximum number of items
        if isItemLimitReached {
            return
        }
        
        // Create a new item with no group
        let newItem = Models.ChecklistItem(
            title: title, 
            date: date, 
            isCompleted: false, 
            notification: nil, 
            group: nil
        )
        checklist.addItem(newItem)
        saveChecklist()
        
        // Check if we've just reached the maximum number of items
        if checklist.items.count == maxItemsPerDay {
            showingImportLimitAlert = true
        }
    }
    
    func addItem(_ item: Models.ChecklistItem, at index: Int) {
        // Check if we've reached the maximum number of items
        if isItemLimitReached {
            return
        }
        
        var updatedChecklist = checklist
        let safeIndex = min(max(index, 0), updatedChecklist.items.count)
        
        // Ensure the item has the correct date
        var newItem = item
        if !Calendar.current.isDate(item.date, inSameDayAs: date) {
            // Get the group if it exists
            let group = item.group ?? (item.groupId != nil ? groupStore.getGroup(by: item.groupId!) : nil)
            
            // Create a new item with the correct date
            newItem = Models.ChecklistItem(
                id: item.id,
                title: item.title,
                date: date,
                isCompleted: item.isCompleted,
                notification: item.notification,
                group: group
            )
        }
        
        updatedChecklist.items.insert(newItem, at: safeIndex)
        checklist = updatedChecklist
        
        // Schedule notification if needed
        if let notification = newItem.notification,
           !newItem.isCompleted,
           notification > Date() {
            notificationManager.scheduleNotification(for: newItem, in: checklist)
        }
        
        saveChecklist()
        
        // Check if we've just reached the maximum number of items
        if checklist.items.count == maxItemsPerDay {
            showingImportLimitAlert = true
        }
    }
    
    func moveItems(from source: IndexSet, to destination: Int) {
        var updatedChecklist = checklist
        updatedChecklist.moveItems(from: source, to: destination)
        checklist = updatedChecklist
        saveChecklist()
    }
    
    private func saveChecklist() {
        persistence.saveChecklist(checklist)
    }
    
    // MARK: - Group Management
    
    func updateItemGroup(_ item: Models.ChecklistItem, with groupId: UUID?) {
        // If the item already belongs to a group, remove it from that group
        if let oldGroupId = item.groupId {
            groupStore.removeItemFromGroup(itemId: item.id, groupId: oldGroupId)
        }
        
        // Create an updated item with the new group
        var updatedItem = item
        
        if let newGroupId = groupId {
            // Get the actual group object
            let newGroup = groupStore.getGroup(by: newGroupId)
            updatedItem.updateGroup(newGroup)
            
            // Add the item to the group
            groupStore.addItemToGroup(item: updatedItem, groupId: newGroupId)
        } else {
            // Clear the group
            updatedItem.updateGroup(nil)
        }
        
        // Update the item in the checklist
        checklist.updateItem(updatedItem)
        saveChecklist()
    }
    
    func getGroupForItem(_ item: Models.ChecklistItem) -> Models.ItemGroup? {
        // Use the direct group reference if available
        if let group = item.group {
            return group
        }
        
        // Fallback to looking up by ID for backward compatibility
        guard let groupId = item.groupId else { return nil }
        return groupStore.getGroup(by: groupId)
    }
    
    // MARK: - Notes Management
    
    func updateNotes(_ newNotes: String) {
        var updatedChecklist = checklist
        updatedChecklist.updateNotes(newNotes)
        checklist = updatedChecklist
        saveChecklist()
    }
    
    func toggleNotesView() {
        isShowingNotes.toggle()
        UserDefaults.standard.set(isShowingNotes, forKey: "isShowingNotes")
    }
    
    // MARK: - Import Functionality
    
    func importItems(from sourceDate: Date, importIncompleteOnly: Bool) {
        // Load the source checklist
        guard let sourceChecklist = persistence.loadChecklist(for: sourceDate) else { return }
        
        // Create deep copies of the items to import with the current date
        let itemsToImport = sourceChecklist.items
            .filter { !importIncompleteOnly || !$0.isCompleted } // Filter based on importIncompleteOnly
            .map { sourceItem -> Models.ChecklistItem in
                // Get the group if it exists
                let group = sourceItem.group ?? (sourceItem.groupId != nil ? groupStore.getGroup(by: sourceItem.groupId!) : nil)
                
                // Create a new item with a new ID but keep the group
                let newItem = Models.ChecklistItem(
                    id: UUID(),
                    title: sourceItem.title,
                    date: self.date,
                    isCompleted: false, // Always set as incomplete when importing
                    notification: nil, // Reset notifications
                    group: group
                )
                
                // Add to group if needed
                if let group = newItem.group {
                    groupStore.addItemToGroup(item: newItem, groupId: group.id)
                }
                
                return newItem
            }
        
        // Calculate how many items we can import without exceeding the limit
        let currentCount = checklist.items.count
        let availableSlots = maxItemsPerDay - currentCount
        
        // Check if we need to truncate the import
        if itemsToImport.count > availableSlots {
            // Show alert that some items were not imported
            showingImportLimitAlert = true
        }
        
        // Only import up to the available slots
        let itemsToActuallyImport = itemsToImport.prefix(availableSlots)
        
        // Update the checklist by appending the new items
        var updatedChecklist = checklist
        updatedChecklist.items.append(contentsOf: itemsToActuallyImport)
        checklist = updatedChecklist
        saveChecklist()
    }
    
    // MARK: - Refresh Functionality
    
    func reloadChecklist() {
        // Reload the checklist from persistence
        let reloadedChecklist = persistence.loadChecklist(for: date) ?? Models.Checklist(date: date)
        self.checklist = reloadedChecklist
    }
} 
