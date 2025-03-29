import Foundation
import SwiftUI
import Combine

// Add debug helper function at the top
private func debugLog(_ source: String, _ action: String) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    print("\(timestamp) [EasyListViewModel]: \(source) - \(action)")
}

// Simple structure to hold group information for UI purposes
struct GroupInfo {
    let id: UUID
    let title: String
    let colorRed: Double
    let colorGreen: Double
    let colorBlue: Double
    let hasColor: Bool
    
    init(from group: Models.ItemGroup) {
        self.id = group.id
        self.title = group.title
        self.colorRed = group.colorRed
        self.colorGreen = group.colorGreen
        self.colorBlue = group.colorBlue
        self.hasColor = group.hasColor
    }
    
    // Helper to convert to SwiftUI Color
    var color: Color? {
        guard hasColor else { return nil }
        return Color(red: colorRed, green: colorGreen, blue: colorBlue)
    }
}

// UI-only data structure for PlannerItemView
struct PlannerItemDisplayData: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let notification: Date?
    let groupId: UUID?
    let groupTitle: String?
    let groupColor: Color?
    let subItems: [SubItemDisplayData]
    let date: Date  // For API compatibility when needed
    
    struct SubItemDisplayData: Identifiable, Equatable {
        let id: UUID
        let title: String
        let isCompleted: Bool
    }
    
    // Create display data from a model item
    static func from(item: Models.ChecklistItem, groupsCache: [UUID: GroupInfo]) -> PlannerItemDisplayData {
        // Look up group information if present
        let groupInfo: GroupInfo? = item.groupId.flatMap { groupsCache[$0] }
        
        // If we have a direct group reference, use that instead
        let groupColor: Color?
        let groupTitle: String?
        
        if let group = item.group, group.hasColor {
            groupColor = Color(red: group.colorRed, green: group.colorGreen, blue: group.colorBlue)
            groupTitle = group.title
        } else {
            groupColor = groupInfo?.color
            groupTitle = groupInfo?.title
        }
        
        return PlannerItemDisplayData(
            id: item.id,
            title: item.title,
            isCompleted: item.isCompleted,
            notification: item.notification,
            groupId: item.groupId,
            groupTitle: groupTitle,
            groupColor: groupColor,
            subItems: item.subItems.map { subItem in
                SubItemDisplayData(
                    id: subItem.id,
                    title: subItem.title,
                    isCompleted: subItem.isCompleted
                )
            },
            date: item.date
        )
    }
}

@MainActor
final class EasyListViewModel: ObservableObject {
    @Published private(set) var date: Date
    @Published var checklist: Models.Checklist
    @Published var isShowingNotes: Bool
    @Published var showingImportLimitAlert = false
    @Published private(set) var isLoading = false
    private let persistence = ChecklistPersistence.shared
    private let notificationManager = NotificationManager.shared
    private let groupStore = GroupStore.shared
    
    // Cache of groups for faster lookup and passing to views
    @Published private(set) var groupsCache: [UUID: GroupInfo] = [:]
    
    // Flag to track if changes need to be saved
    private var hasUnsavedChanges = false
    
    // Maximum number of items allowed per day
    private let maxItemsPerDay = 99
    
    // Check if the item limit is reached
    var isItemLimitReached: Bool {
        return checklist.items.count >= maxItemsPerDay
    }
    
    init(date: Date = Date()) {
        self.date = date
        // Initialize with empty checklist instead of loading data immediately
        self.checklist = Models.Checklist(date: date)
        self.isShowingNotes = UserDefaults.standard.bool(forKey: "isShowingNotes")
        
        // Don't clean up empty items on init - defer until loadData is called
    }
    
    // New method to load data - this will be called from the view's onAppear
    func loadData() {
        // Set loading state to true
        isLoading = true
        
        // Load the checklist for the current date
        self.checklist = persistence.loadChecklist(for: date) ?? Models.Checklist(date: date)
        
        // Clean up any empty items after loading
        let emptyIndices = checklist.items.enumerated().filter { $0.element.title.isEmpty }.map { $0.offset }
        if !emptyIndices.isEmpty {
            deleteItems(at: IndexSet(emptyIndices))
        }
        
        // Set loading state to false
        isLoading = false
    }
    
    // New method to update the date without recreating the view model
    func updateToDate(_ newDate: Date) {
        // Skip if it's the same day (using calendar comparison)
        let calendar = Calendar.current
        guard !calendar.isDate(date, inSameDayAs: newDate) else { return }
        
        // If we have unsaved changes, save them before switching dates
        if hasUnsavedChanges {
            saveChecklist()
            hasUnsavedChanges = false
        }
        
        let oldDateString = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        let newDateString = DateFormatter.localizedString(from: newDate, dateStyle: .medium, timeStyle: .short)
        debugLog("updateToDate", "Switching from \(oldDateString) to \(newDateString)")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Update the date first
        self.date = newDate
        
        // Initialize with empty checklist
        self.checklist = Models.Checklist(date: newDate)
        
        // Then load the data
        loadData()
        
        let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        debugLog("updateToDate", "Checklist loaded in \(String(format: "%.2f", duration))ms")
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
    
    /// Finds and returns an item by its ID
    func getItem(id: UUID) -> Models.ChecklistItem? {
        return checklist.items.first { $0.id == id }
    }
    
    /// Deletes an item identified by ID
    func deleteItem(id: UUID) {
        guard let index = checklist.items.firstIndex(where: { $0.id == id }) else { return }
        // Use the existing method to handle cleanup
        deleteItems(at: IndexSet([index]))
    }
    
    /// Updates the notification time for an item
    func updateItemNotification(_ item: Models.ChecklistItem, with notification: Date?) {
        guard let itemIndex = checklist.itemCollection.items.firstIndex(where: { $0.id == item.id }) else { return }
        
        // Directly update the item in the collection
        checklist.itemCollection.items[itemIndex].notification = notification
        
        // Reset completion status if a notification is being set
        if notification != nil {
            checklist.itemCollection.items[itemIndex].isCompleted = false
        }
        
        // Mark changes and save
        hasUnsavedChanges = true
        saveChecklist()
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
        
        // Use the direct reference to delete items
        checklist.deleteItems(at: indexSet)
        hasUnsavedChanges = true
    }
    
    func deleteAllItems() {
        // Process all items before deleting them
        for item in checklist.items {
            cleanupItemReferences(item)
        }
        
        // Use the direct reference to remove all items
        checklist.removeAllItems()
        hasUnsavedChanges = true
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
        
        // Add the item directly to the collection
        checklist.addItem(newItem)
        hasUnsavedChanges = true
        
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
        
        let safeIndex = min(max(index, 0), checklist.items.count)
        
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
        
        // Insert directly into the collection
        checklist.itemCollection.items.insert(newItem, at: safeIndex)
        
        // Schedule notification if needed
        if let notification = newItem.notification,
           !newItem.isCompleted,
           notification > Date() {
            notificationManager.scheduleNotification(for: newItem, in: checklist)
        }
        
        hasUnsavedChanges = true
        
        // Check if we've just reached the maximum number of items
        if checklist.items.count == maxItemsPerDay {
            showingImportLimitAlert = true
        }
    }
    
    func moveItems(from source: IndexSet, to destination: Int) {
        // Use the collection directly
        checklist.moveItems(from: source, to: destination)
        hasUnsavedChanges = true
    }
    
    func saveChecklist() {
        if hasUnsavedChanges {
            debugLog("saveChecklist()", "Saving checklist")
            persistence.saveChecklist(checklist)
        }
        hasUnsavedChanges = false
    }
    
    // MARK: - Group Management
    
    func updateItemGroup(_ item: Models.ChecklistItem, with groupId: UUID?) {
        guard let itemIndex = checklist.itemCollection.items.firstIndex(where: { $0.id == item.id }) else { return }
        
        // If the item already belongs to a group, remove it from that group
        if let oldGroupId = item.groupId {
            groupStore.removeItemFromGroup(itemId: item.id, groupId: oldGroupId)
        }
        
        if let newGroupId = groupId {
            // Get the actual group object
            let newGroup = groupStore.getGroup(by: newGroupId)
            
            // Update the group directly in the collection
            checklist.itemCollection.items[itemIndex].updateGroup(newGroup)
            
            // Add the item to the group
            let updatedItem = checklist.itemCollection.items[itemIndex]
            groupStore.addItemToGroup(item: updatedItem, groupId: newGroupId)
        } else {
            // Clear the group
            checklist.itemCollection.items[itemIndex].updateGroup(nil)
        }
        
        // Mark changes to save later - consistent with other operations
        hasUnsavedChanges = true
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
        // Only update and mark as changed if the notes actually changed
        if checklist.notes != newNotes {
            // Update notes directly
            checklist.updateNotes(newNotes)
            hasUnsavedChanges = true
        }
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
                
                // Create new copies of subitems with new IDs
                let newSubItems = sourceItem.subItems.map { subItem in
                    let newId = UUID()
                    return Models.SubItem(id: newId, title: subItem.title, isCompleted: subItem.isCompleted)
                }
                
                // Create a new item with a new ID but keep the group
                let newItem = Models.ChecklistItem(
                    id: UUID(),
                    title: sourceItem.title,
                    date: self.date,
                    isCompleted: sourceItem.isCompleted, // Keep completion status of subitems
                    notification: nil, // Reset notifications
                    group: group,
                    subItems: newSubItems  // Add the copied subitems
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
        
        // Update the checklist by appending the new items directly to the collection
        checklist.itemCollection.items.append(contentsOf: itemsToActuallyImport)
        hasUnsavedChanges = true
    }
    
    // MARK: - Refresh Functionality
    
    func reloadChecklist() {
        // Reload the checklist from persistence
        let reloadedChecklist = persistence.loadChecklist(for: date) ?? Models.Checklist(date: date)
        self.checklist = reloadedChecklist
        
        // Process notifications for the loaded checklist
        _ = notificationManager.processNotificationsForChecklist(reloadedChecklist)
    }
    
    // MARK: - Item Toggling
    
    /// Toggles the completion state of a main checklist item
    func toggleItemCompletion(_ item: Models.ChecklistItem) {
        guard let itemIndex = checklist.itemCollection.items.firstIndex(where: { $0.id == item.id }) else { return }
        
        // Update the item in the checklist collection with the isCompleted state from the parameter
        checklist.itemCollection.items[itemIndex].isCompleted = item.isCompleted
        
        // Mark changes for later saving
        hasUnsavedChanges = true
    }
    
    /// Toggles the completion state of a main checklist item by ID
    func toggleItemCompletion(itemId: UUID) {
        guard let itemIndex = checklist.itemCollection.items.firstIndex(where: { $0.id == itemId }) else { return }
        
        // Toggle the item's completion state
        checklist.itemCollection.items[itemIndex].isCompleted.toggle()
        
        // Mark changes for later saving
        hasUnsavedChanges = true
    }
    
    /// Toggles the completion state of a sub-item
    func toggleSubItemCompletion(_ mainItemId: UUID, subItemId: UUID, isCompleted: Bool) {
        // Find the main item
        guard let itemIndex = checklist.itemCollection.items.firstIndex(where: { $0.id == mainItemId }) else { return }
        
        // Find the sub-item
        guard let subItemIndex = checklist.itemCollection.items[itemIndex].subItemCollection.items.firstIndex(where: { $0.id == subItemId }) else { return }
        
        // Update the sub-item's completion state
        checklist.itemCollection.items[itemIndex].subItemCollection.items[subItemIndex].isCompleted = isCompleted
        
        // Update parent item completion based on subitems
        let allSubItemsCompleted = checklist.itemCollection.items[itemIndex].subItems.allSatisfy { $0.isCompleted }
        let anySubItemsIncomplete = checklist.itemCollection.items[itemIndex].subItems.contains { !$0.isCompleted }
        
        // If all subitems are complete, mark parent complete
        if !checklist.itemCollection.items[itemIndex].subItems.isEmpty && allSubItemsCompleted {
            checklist.itemCollection.items[itemIndex].isCompleted = true
        }
        // If any subitems are incomplete, mark parent incomplete
        else if anySubItemsIncomplete {
            checklist.itemCollection.items[itemIndex].isCompleted = false
        }
        
        // Mark changes for later saving
        hasUnsavedChanges = true
    }
    
    // MARK: - Display Data
    
    /// Converts a ChecklistItem to a PlannerItemDisplayData for UI rendering
    func getDisplayData(for item: Models.ChecklistItem) -> PlannerItemDisplayData {
        return PlannerItemDisplayData.from(item: item, groupsCache: groupsCache)
    }
    
    /// Gets display data for all items
    func getAllDisplayData() -> [PlannerItemDisplayData] {
        return checklist.items.map { getDisplayData(for: $0) }
    }
    
    // MARK: - Item Properties Update Methods
    
    /// Updates the notification for a specific item by ID
    func updateItemNotification(itemId: UUID, with notification: Date?) {
        guard let itemIndex = checklist.itemCollection.items.firstIndex(where: { $0.id == itemId }) else { return }
        
        // Directly update the notification in the collection
        checklist.itemCollection.items[itemIndex].notification = notification
        
        // Reset completion status if a notification is being set
        if notification != nil {
            checklist.itemCollection.items[itemIndex].isCompleted = false
        }
        
        // Mark changes and save
        hasUnsavedChanges = true
        saveChecklist()
    }
    
    /// Updates the group for a specific item by ID
    func updateItemGroup(itemId: UUID, with groupId: UUID?) {
        guard let itemIndex = checklist.itemCollection.items.firstIndex(where: { $0.id == itemId }) else { return }
        let item = checklist.itemCollection.items[itemIndex]
        
        // If the item already belongs to a group, remove it from that group
        if let oldGroupId = item.groupId {
            groupStore.removeItemFromGroup(itemId: item.id, groupId: oldGroupId)
        }
        
        if let newGroupId = groupId {
            // Get the actual group object
            let newGroup = groupStore.getGroup(by: newGroupId)
            
            // Update the group directly in the collection
            checklist.itemCollection.items[itemIndex].updateGroup(newGroup)
            
            // Add the item to the group
            let updatedItem = checklist.itemCollection.items[itemIndex]
            groupStore.addItemToGroup(item: updatedItem, groupId: newGroupId)
        } else {
            // Clear the group
            checklist.itemCollection.items[itemIndex].updateGroup(nil)
        }
        
        // Mark changes to save later - consistent with other operations
        hasUnsavedChanges = true
    }
    
    /// Updates the title for a specific item by ID
    func updateItemTitle(itemId: UUID, with title: String) {
        guard let itemIndex = checklist.itemCollection.items.firstIndex(where: { $0.id == itemId }) else { return }
        
        // Update the title
        checklist.itemCollection.items[itemIndex].title = title
        
        // Mark changes for later saving
        hasUnsavedChanges = true
    }
} 
