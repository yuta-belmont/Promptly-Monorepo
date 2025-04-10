import Foundation
import SwiftUI
import Combine

// Define undo action types
enum UndoAction {
    case snapshot(items: [Models.ChecklistItem])
}

// Separate class to manage undo state
class UndoStateManager: ObservableObject {
    @Published var canUndo: Bool = false
    private var undoCache: [UndoAction] = []
    private let maxUndoActions = 10
    
    func addToUndoCache(_ action: UndoAction) {
        undoCache.insert(action, at: 0)
        if undoCache.count > maxUndoActions {
            undoCache.removeLast()
        }
        canUndo = !undoCache.isEmpty
    }
    
    func clearCache() {
        undoCache.removeAll()
        canUndo = false
    }
    
    func getNextAction() -> UndoAction? {
        guard !undoCache.isEmpty else { return nil }
        let action = undoCache.removeFirst()
        canUndo = !undoCache.isEmpty
        return action
    }
}

// Separate class to manage counter state for the footer
class CounterStateManager: ObservableObject {
    @Published var completedCount: Int = 0
    @Published var totalCount: Int = 0
    
    func updateCounts(completed: Int, total: Int) {
        completedCount = completed
        totalCount = total
    }
}

// Simple structure to hold group information for UI purposes
public struct GroupInfo {
    public let title: String
    public let color: Color?
    
    public init(title: String, color: Color?) {
        self.title = title
        self.color = color
    }
}

// UI-only data structure for PlannerItemView
public struct PlannerItemDisplayData: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let isCompleted: Bool
    public let notification: Date?
    public let groupId: UUID?
    public let groupTitle: String?
    public let groupColor: Color?
    public let subItems: [SubItemDisplayData]
    public let date: Date  // For API compatibility when needed
    public let lastModified: Date? // Optional timestamp for forcing view updates
    public let areSubItemsExpanded: Bool // New property to track expansion state
    
    public struct SubItemDisplayData: Identifiable, Equatable {
        public let id: UUID
        public let title: String
        public let isCompleted: Bool
    }
    
    // Create display data from a model item
    static func from(item: Models.ChecklistItem, groupsCache: [UUID: GroupInfo], expandedItems: Set<UUID> = []) -> PlannerItemDisplayData {
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
        
        // Check if this item's ID is in the expanded set
        let isExpanded = expandedItems.contains(item.id)
        
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
            date: item.date,
            lastModified: item.lastModified,
            areSubItemsExpanded: isExpanded
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
    
    // Replace direct undo cache with the manager
    let undoManager = UndoStateManager()
    var canUndo: Bool { undoManager.canUndo }
    
    // Add counter state manager
    let counterManager = CounterStateManager()
    
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
    
    // Add a set to track which item IDs are expanded
    @Published private var expandedItemIds: Set<UUID> = []
    
    init(date: Date = Date()) {
        self.date = date
        // Initialize with empty checklist instead of loading data immediately
        self.checklist = Models.Checklist(date: date)
        self.isShowingNotes = UserDefaults.standard.bool(forKey: "isShowingNotes")
        
        // Set up notification listeners for subitem changes
        setupSubitemChangeListeners()
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
        
        // Clean up expanded states for items that no longer exist or have no subitems
        cleanupExpandedStates()
        
        // Update counter state
        counterManager.updateCounts(completed: checklist.items.filter { $0.isCompleted }.count, total: checklist.items.count)
        
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
                
        // Clear the undo cache when switching days
        undoManager.clearCache()
        
        // Clear expanded states when switching dates
        expandedItemIds.removeAll()
        
        // Update the date first
        self.date = newDate
        
        // Initialize with empty checklist
        self.checklist = Models.Checklist(date: newDate)
        
        // Then load the data
        loadData()
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
        
        // Capture a snapshot of the entire checklist before deletion
        let snapshot = checklist.items
        
        // Add snapshot to undo cache using the manager
        undoManager.addToUndoCache(.snapshot(items: snapshot))
        
        // Use the existing method to handle cleanup
        deleteItemsWithoutUndo(at: IndexSet([index]))
    }
    
    /// Deletes an item identified by ID without adding to undo cache
    func deleteItemWithoutUndo(id: UUID) {
        guard let index = checklist.items.firstIndex(where: { $0.id == id }) else { return }
        // Use the method that doesn't add to undo cache
        deleteItemsWithoutUndo(at: IndexSet([index]))
    }
    
    func deleteItems(at indexSet: IndexSet) {
        // Check if there are actually items to delete
        guard !indexSet.isEmpty else { return }
        
        // Capture a snapshot of the entire checklist before deletion
        let snapshot = checklist.items
        
        // Process items before deleting them
        for index in indexSet {
            if index < checklist.items.count {
                let item = checklist.items[index]
                // Remove from any groups and remove notifications in one pass
                cleanupItemReferences(item)
            }
        }
        
        // Add snapshot to undo cache using the manager
        undoManager.addToUndoCache(.snapshot(items: snapshot))
        
        // Use the direct reference to delete items
        checklist.deleteItems(at: indexSet)
        hasUnsavedChanges = true
        
        // Clean up expanded states
        cleanupExpandedStates()
        
        // Update counter state after deletion
        counterManager.updateCounts(completed: checklist.items.filter { $0.isCompleted }.count, total: checklist.items.count)
    }
    
    func deleteAllItems() {
        // Check if there are actually items to delete
        guard !checklist.items.isEmpty else { return }
        
        // Capture a snapshot of the entire checklist before deletion
        let snapshot = checklist.items
        
        // Process all items before deleting them
        for item in checklist.items {
            cleanupItemReferences(item)
        }
        
        // Add snapshot to undo cache using the manager
        undoManager.addToUndoCache(.snapshot(items: snapshot))
        
        // Use the direct reference to remove all items
        checklist.removeAllItems()
        hasUnsavedChanges = true
        
        // Update counter state after deletion
        counterManager.updateCounts(completed: 0, total: 0)
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
        
        // Insert the item at the beginning of the collection (index 0) instead of appending
        checklist.addItemAtBeginning(newItem)
        hasUnsavedChanges = true
        
        // Clear the undo cache when adding items
        undoManager.clearCache()
        
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
        
        // Clear the undo cache when adding items
        undoManager.clearCache()
        
        // Check if we've just reached the maximum number of items
        if checklist.items.count == maxItemsPerDay {
            showingImportLimitAlert = true
        }
    }
    
    func moveItems(from source: IndexSet, to destination: Int) {
        // Use the collection directly
        checklist.moveItems(from: source, to: destination)
        hasUnsavedChanges = true
        
        // Clear the undo cache when moving items
        undoManager.clearCache()
    }
    
    func saveChecklist() {
        if hasUnsavedChanges {
            persistence.saveChecklist(checklist)
        }
        hasUnsavedChanges = false
    }
    
    // MARK: - Group Management
    
    /// Updates the group for a specific item by ID
    func updateItemGroup(itemId: UUID, with groupId: UUID?) {
        guard let itemIndex = checklist.itemCollection.items.firstIndex(where: { $0.id == itemId }) else { 
            return 
        }
        
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
        
        // Clear the undo cache when updating item group
        undoManager.clearCache()
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
            
            // Clear the undo cache when updating notes
            undoManager.clearCache()
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
        
        // Check if there are actually items to import
        guard !itemsToImport.isEmpty else { return }
        
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
        
        // Check if there are still items to import after truncation
        guard !itemsToActuallyImport.isEmpty else { return }
        
        // Capture a snapshot of the entire checklist before import
        let snapshot = checklist.items
        
        // Add to undo cache before importing
        undoManager.addToUndoCache(.snapshot(items: snapshot))
        
        // Update the checklist by appending the new items directly to the collection
        checklist.itemCollection.items.append(contentsOf: itemsToActuallyImport)
        hasUnsavedChanges = true
        saveChecklist()
        reloadChecklist()
    }
    
    // MARK: - Refresh Functionality
    
    func reloadChecklist() {
        
        // Reload the checklist from persistence
        let reloadedChecklist = persistence.loadChecklist(for: date) ?? Models.Checklist(date: date)
        self.checklist = reloadedChecklist
        
        // Process notifications for the loaded checklist
        _ = notificationManager.processNotificationsForChecklist(reloadedChecklist)
        
        // Clean up expanded states for items that no longer exist or have no subitems
        cleanupExpandedStates()
        
        // Update counter state
        counterManager.updateCounts(completed: checklist.items.filter { $0.isCompleted }.count, total: checklist.items.count)
    }
    
    // MARK: - Item Toggling
    
    /// Toggles the completion state of a main checklist item by ID
    func toggleItemCompletion(itemId: UUID) {
        guard let itemIndex = checklist.itemCollection.items.firstIndex(where: { $0.id == itemId }) else { return }
        
        // Toggle the item's completion state
        checklist.itemCollection.items[itemIndex].isCompleted.toggle()
        
        // Clear the undo cache when toggling items
        undoManager.clearCache()
        
        // Mark changes for later saving
        hasUnsavedChanges = true
        
        // Update counter state
        counterManager.updateCounts(completed: checklist.items.filter { $0.isCompleted }.count, total: checklist.items.count)
    }
    
    /// Toggles the completion state of a sub-item
    func toggleSubItemCompletion(_ mainItemId: UUID, subItemId: UUID, isCompleted: Bool) {
        // Find the main item
        guard let itemIndex = checklist.itemCollection.items.firstIndex(where: { $0.id == mainItemId }) else { return }
        
        // Find the sub-item
        guard let subItemIndex = checklist.itemCollection.items[itemIndex].subItemCollection.items.firstIndex(where: { $0.id == subItemId }) else { return }
        
        // Update the sub-item's completion state
        checklist.itemCollection.items[itemIndex].subItemCollection.items[subItemIndex].isCompleted = isCompleted
        
        // Clear the undo cache when toggling sub-items
        undoManager.clearCache()
        
        // Mark changes for later saving
        hasUnsavedChanges = true
        
        // Update counter state
        counterManager.updateCounts(completed: checklist.items.filter { $0.isCompleted }.count, total: checklist.items.count)
    }
    
    // Add a new method to manage subitem state and clean up expanded state if needed
    func checkAndUpdateSubitemsState(_ itemId: UUID) {
        guard let item = getItem(id: itemId) else { return }
        
        // If the item has no subitems but is in the expanded set, remove it
        if item.subItems.isEmpty && expandedItemIds.contains(itemId) {
            expandedItemIds.remove(itemId)
            objectWillChange.send()
        }
    }
    
    // Listen for notifications from ItemDetailsView about subitem changes
    func setupSubitemChangeListeners() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleItemDetailsUpdated(_:)), name: Notification.Name("ItemDetailsUpdated"), object: nil)
    }
    
    @objc private func handleItemDetailsUpdated(_ notification: Notification) {
        // Get the item ID from the notification
        if let itemId = notification.object as? UUID {
            // Check and update the item's expanded state
            checkAndUpdateSubitemsState(itemId)
            
            // Mark changes for later saving
            hasUnsavedChanges = true
            
            // Force a refresh of the UI
            objectWillChange.send()
        }
    }
    
    // MARK: - Display Data
    
    /// Converts a ChecklistItem to a PlannerItemDisplayData for UI rendering
    func getDisplayData(for item: Models.ChecklistItem) -> PlannerItemDisplayData {
        return PlannerItemDisplayData.from(item: item, groupsCache: groupsCache, expandedItems: expandedItemIds)
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
        
        // Update notification directly
        let updatedItem = checklist.itemCollection.items[itemIndex]
        notificationManager.updateNotificationForEditedItem(updatedItem, in: checklist)
        
        // Mark changes and save
        hasUnsavedChanges = true
        
        // Clear the undo cache when updating item notification
        undoManager.clearCache()
    }
    
    /// Updates the title for a specific item by ID
    func updateItemTitle(itemId: UUID, with title: String) {
        guard let itemIndex = checklist.itemCollection.items.firstIndex(where: { $0.id == itemId }) else { return }
        
        // Update the title
        checklist.itemCollection.items[itemIndex].title = title
        
        // Mark changes for later saving
        hasUnsavedChanges = true
        
        // Clear the undo cache when updating item title
        undoManager.clearCache()
    }
    
    // MARK: - Undo Functionality
    
    /// Deletes items without adding to undo cache - used for undo operations
    private func deleteItemsWithoutUndo(at indexSet: IndexSet) {
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
        
        // Clean up expanded states
        cleanupExpandedStates()
        
        // Update counter state after deletion
        counterManager.updateCounts(completed: checklist.items.filter { $0.isCompleted }.count, total: checklist.items.count)
    }
    
    func undo() {
        // Get the next action from the manager
        guard let action = undoManager.getNextAction() else { return }
        
        // Perform the undo operation
        switch action {
        case .snapshot(let items):
            // Remove all current items
            checklist.removeAllItems()
            
            // Add the snapshots items back in their original order
            for item in items {
                checklist.itemCollection.items.append(item)
            }
        }
        
        // Save changes
        saveChecklist()
        
        // Force a UI refresh by updating the checklist property
        // This ensures SwiftUI knows the data has changed
        let updatedChecklist = checklist
        checklist = updatedChecklist
    }
    
    // Add this method before the last closing brace
    func getChecklistForCheckin() -> Models.Checklist {
        return checklist
    }
    
    func getChecklistDictionaryForCheckin() -> [String: Any] {
        return [
            "date": checklist.date.ISO8601Format(),
            "items": checklist.items.map { item in
                var itemDict: [String: Any] = [
                    "title": item.title,
                    "isCompleted": item.isCompleted,
                    "group": item.group?.title ?? "Uncategorized"
                ]
                
                // Add notification if exists
                if let notification = item.notification {
                    itemDict["notification"] = notification.ISO8601Format()
                }
                
                // Add subitems if they exist
                itemDict["subitems"] = item.subItems.map { subItem in
                    [
                        "title": subItem.title,
                        "isCompleted": subItem.isCompleted
                    ]
                }
                
                return itemDict
            }
        ]
    }
    
    // Add methods to toggle and get expansion state
    func toggleItemExpanded(_ itemId: UUID) {
        if expandedItemIds.contains(itemId) {
            expandedItemIds.remove(itemId)
        } else {
            // Only add to expanded set if the item has subitems
            if let item = getItem(id: itemId), !item.subItems.isEmpty {
                expandedItemIds.insert(itemId)
            }
        }
        objectWillChange.send()
    }
    
    func isItemExpanded(_ itemId: UUID) -> Bool {
        // Only return true if the item has subitems and is in the expanded set
        if let item = getItem(id: itemId), item.subItems.isEmpty {
            // If item has no subitems, remove it from expanded set if it's there
            if expandedItemIds.contains(itemId) {
                expandedItemIds.remove(itemId)
            }
            return false
        }
        return expandedItemIds.contains(itemId)
    }
    
    // Add a method to clean up expanded states that are no longer valid
    private func cleanupExpandedStates() {
        // Find all items in expanded set that no longer exist or have no subitems
        let invalidIds = expandedItemIds.filter { itemId in
            guard let item = getItem(id: itemId) else {
                // Item doesn't exist anymore
                return true
            }
            // Item exists but has no subitems
            return item.subItems.isEmpty
        }
        
        // Remove invalid IDs from expanded set
        for id in invalidIds {
            expandedItemIds.remove(id)
        }
    }
} 
