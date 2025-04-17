import Foundation
import SwiftUI
import Combine

// Add debug helper function at the top

// Define undo action types for subitems
enum SubItemUndoAction {
    case snapshot(items: [Models.SubItem])
}

// Separate class to manage undo state for subitems
class SubItemUndoStateManager: ObservableObject {
    @Published var canUndo: Bool = false
    private var undoCache: [SubItemUndoAction] = []
    private let maxUndoActions = 10
    
    func addToUndoCache(_ action: SubItemUndoAction) {
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
    
    func getNextAction() -> SubItemUndoAction? {
        guard !undoCache.isEmpty else { return nil }
        let action = undoCache.removeFirst()
        canUndo = !undoCache.isEmpty
        return action
    }
}

@MainActor
final class ItemDetailsViewModel: ObservableObject {
    @Published var item: Models.ChecklistItem
    @Published var isLoading: Bool = false
    
    private let persistence = ChecklistPersistence.shared
    private let notificationManager = NotificationManager.shared
    let groupStore = GroupStore.shared
    private var cancellables = Set<AnyCancellable>()
    private let undoManager = SubItemUndoStateManager()
    
    init(item: Models.ChecklistItem) {
        self.item = item
        
        // Load the fresh item from persistence immediately during initialization
        // This ensures we start with the most current data
        Task {
            await loadFreshItemData()
        }
    }
    
    deinit {
        // Clean up resources if needed
    }
    
    // Format notification time for display
    func formatNotificationTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
    
    // Add a new subitem to the item
    func addSubitem(_ title: String, _ toTop: Bool = false ) {
        // Create a new subitem
        let newSubitem = Models.SubItem(
            id: UUID(),
            title: title,
            isCompleted: false
        )
        
        // Create a mutable copy of the item
        var mutableItem = item
        
        // Insert the subitem at the beginning of the array instead of appending
        if toTop {
            mutableItem.subItems.insert(newSubitem, at: 0)

        } else {
            mutableItem.subItems.append(newSubitem)
        }
        
        // If the parent item was previously completed, mark it incomplete
        // since we've added a new incomplete subitem
        if mutableItem.isCompleted {
            mutableItem.isCompleted = false
        }
        
        // Update the published item
        item = mutableItem
        
        // Clear undo cache before saving
        undoManager.clearCache()
        
        // Save to persistence
        saveItem()
    }
    
    // Public method to save changes when view disappears
    func saveChanges()
    {
        saveItem()
    }
    
    // Save the updated item to persistence
    private func saveItem() {
        // Load the current checklist for the item's date
        guard var checklist = persistence.loadChecklist(for: item.date) else {
            // If no checklist exists for this date, create a new one
            var newChecklist = Models.Checklist(date: item.date)
            newChecklist.addItem(item)
            persistence.saveChecklist(newChecklist)
            return
        }
        item.lastModified = Date()

        // Find the item in the checklist and update it
        if let itemIndex = checklist.itemCollection.items.firstIndex(where: { $0.id == item.id }) {
            // The item exists in the checklist, directly update it
            checklist.itemCollection.items[itemIndex] = item
        } else {
            // The item doesn't exist in the checklist, add it
            checklist.addItem(item)
        }
        
        // Save the updated checklist
        persistence.saveChecklist(checklist)
    }
    
    // Helper method to load fresh item data during initialization
    private func loadFreshItemData() async {
        await MainActor.run {
            // Get the latest checklist for the item's date
            if let checklist = persistence.loadChecklist(for: item.date),
               let freshItem = checklist.items.first(where: { $0.id == item.id }) {
                // Update our item with the fresh data if found
                self.item = freshItem
            }
        }
    }
    
    // Load the latest version of the item from persistence
    func loadDetails() {
        isLoading = true
        
        // Get the latest checklist for the item's date
        if let checklist = persistence.loadChecklist(for: item.date) {
            // Find the latest version of the item in the checklist
            if let freshItem = checklist.items.first(where: { $0.id == item.id }) {
                // Update the item with the latest data
                self.item = freshItem
            }
        }
        
        // Mark loading as complete
        isLoading = false
    }
    
    // MARK: - PopoverContentView Support Methods
    
    // Update notification for the item
    func updateNotification(_ newNotification: Date?) {
        // Cancel existing notification if there is one
        if let _ = item.notification {
            // Use the correct method to remove notifications
            notificationManager.removeAllNotificationsForItem(item)
        }
        
        // Update the item with the new notification date
        var mutableItem = item
        mutableItem.notification = newNotification
        item = mutableItem
        
        // Schedule new notification if needed
        if let _ = newNotification {
            // Get the current checklist for the item's date
            if let checklist = persistence.loadChecklist(for: item.date) {
                // Schedule the notification with both required parameters
                notificationManager.scheduleNotification(for: item, in: checklist)
            } else {
                // If no existing checklist, create a temporary one for notification scheduling
                var tempChecklist = Models.Checklist(date: item.date)
                tempChecklist.addItem(item)
                notificationManager.scheduleNotification(for: item, in: tempChecklist)
            }
        }
        
        // Save changes to persistence
        saveItem()
    }
    
    // Update group for the item
    func updateGroup(_ newGroupId: UUID?) {
        // Create a mutable copy of the item
        var mutableItem = item
        
        if let newGroupId = newGroupId {
            // Get the group from the GroupStore
            if let group = groupStore.getGroup(by: newGroupId) {
                // Use the updateGroup method to set the group reference
                mutableItem.updateGroup(group)
            } else {
                // Group not found, clear the group
                mutableItem.updateGroup(nil)
            }
        } else {
            // Clear the group if newGroupId is nil
            mutableItem.updateGroup(nil)
        }
        
        // Update the published item
        item = mutableItem
        
        // Save changes to persistence
        saveItem()
        
        // Post notification that group was updated
        NotificationCenter.default.post(
            name: NSNotification.Name("ItemGroupUpdated"),
            object: item.id
        )
    }
    
    // Toggle the completed state of the item
    func toggleCompleted() {
        // Create a mutable copy of the item
        var mutableItem = item
        
        // Toggle the completion state
        mutableItem.isCompleted.toggle()
        
        // Update notification if needed
        if mutableItem.isCompleted {
            // If item is now completed, remove any notification
            if mutableItem.notification != nil {
                notificationManager.removeAllNotificationsForItem(item)
            }
        } else if let notification = mutableItem.notification, notification > Date() {
            // If item is now incomplete and has a future notification, reschedule it
            if let checklist = persistence.loadChecklist(for: item.date) {
                notificationManager.scheduleNotification(for: mutableItem, in: checklist)
            }
        }
        
        // Update the published item
        item = mutableItem
        
        // Clear undo cache before saving
        undoManager.clearCache()
        
        // Save changes to persistence
        saveItem()
    }
    
    // Toggle the completion state of a subitem
    func toggleSubitemCompleted(subitemId: UUID) {
        // Create a mutable copy of the item
        var mutableItem = item
        
        // Find the subitem and toggle its completion state
        if let subitemIndex = mutableItem.subItems.firstIndex(where: { $0.id == subitemId }) {
            mutableItem.subItems[subitemIndex].isCompleted.toggle()
            
            // Update the published item
            item = mutableItem
            
            // Clear undo cache before saving
            undoManager.clearCache()
            
            // Save changes to persistence
            saveItem()
        }
    }
    
    // Update the title of the item
    func updateTitle(_ newTitle: String) {
        // Create a mutable copy of the item
        var mutableItem = item
        
        // Update the title
        mutableItem.title = newTitle
        
        // Update the published item
        item = mutableItem
        
        // Clear undo cache before saving
        undoManager.clearCache()
        
        // Save changes to persistence
        saveItem()
    }
    
    // Update the title of a subitem
    func updateSubitemTitle(_ subitemId: UUID, newTitle: String) {
        // Create a mutable copy of the item
        var mutableItem = item
        
        // Find the subitem and update its title
        if let subitemIndex = mutableItem.subItems.firstIndex(where: { $0.id == subitemId }) {
            mutableItem.subItems[subitemIndex].title = newTitle
            
            // Update the published item
            item = mutableItem
            
            item.lastModified = Date()
            
            // Clear undo cache before saving
            undoManager.clearCache()
            
            // Save changes to persistence
            saveItem()
        }
    }
    
    // Move a subitem (for drag and drop reordering)
    func moveSubitem(from sourceId: UUID, to destinationId: UUID) {
        // Create a mutable copy of the item
        var mutableItem = item
        
        // Get indices for the source and destination items
        guard let sourceIndex = mutableItem.subItems.firstIndex(where: { $0.id == sourceId }),
              let destinationIndex = mutableItem.subItems.firstIndex(where: { $0.id == destinationId }) else {
            return
        }
        
        // Remove the source item and insert it at the destination index
        let sourceItem = mutableItem.subItems.remove(at: sourceIndex)
        
        // Determine the insert location based on whether destination is before or after source
        if sourceIndex < destinationIndex {
            // If source was before destination, destination index is now one less after removal
            mutableItem.subItems.insert(sourceItem, at: destinationIndex)
        } else {
            // If source was after destination, destination index is unchanged
            mutableItem.subItems.insert(sourceItem, at: destinationIndex)
        }
        
        // Update the published item
        item = mutableItem
        
        // Clear undo cache before saving
        undoManager.clearCache()
        
        // Save changes to persistence
        saveItem()
    }
    
    // Move a subitem to the end of the list
    func moveSubitemToEnd(_ sourceId: UUID) {
        // Create a mutable copy of the item
        var mutableItem = item
        
        // Get index for the source item
        guard let sourceIndex = mutableItem.subItems.firstIndex(where: { $0.id == sourceId }) else {
            return
        }
        
        // Remove the source item and append it to the end
        let sourceItem = mutableItem.subItems.remove(at: sourceIndex)
        mutableItem.subItems.append(sourceItem)
        
        // Update the published item
        item = mutableItem
        
        // Clear undo cache before saving
        undoManager.clearCache()
        
        // Save changes to persistence
        saveItem()
    }
    
    // Handle standard SwiftUI List move operations
    func moveSubitems(from source: IndexSet, to destination: Int) {
        // Create a mutable copy of the item
        var mutableItem = item
        
        // Use the standard move operation on the subItems array
        mutableItem.subItems.move(fromOffsets: source, toOffset: destination)
        
        // Update the published item
        item = mutableItem
        
        // Clear undo cache before saving
        undoManager.clearCache()
        
        // Save changes to persistence
        saveItem()
    }
    
    // Delete a subitem by ID
    func deleteSubitem(_ subitemId: UUID) {
        // Take snapshot before deletion
        let snapshot = item.subItems
        
        // Create a mutable copy of the item
        var mutableItem = item
        
        // Remove the subitem
        let originalCount = mutableItem.subItems.count
        mutableItem.subItems.removeAll { $0.id == subitemId }
        
        // Return early if nothing was deleted
        guard mutableItem.subItems.count < originalCount else { return }
        
        // Add to undo cache since something was deleted
        undoManager.addToUndoCache(.snapshot(items: snapshot))
        
        // Update the published item
        item = mutableItem
        
        // Save changes to persistence
        saveItem()
    }
    
    // Delete all subitems
    func deleteAllSubitems() {
        // Take snapshot before deletion
        let snapshot = item.subItems
        
        // Create a mutable copy of the item
        var mutableItem = item
        
        // Remove all subitems
        let originalCount = mutableItem.subItems.count
        mutableItem.subItems.removeAll()
        
        // Return early if nothing was deleted
        guard mutableItem.subItems.count < originalCount else { return }
        
        // Add to undo cache since something was deleted
        undoManager.addToUndoCache(.snapshot(items: snapshot))
        
        // Update the published item
        item = mutableItem
        
        // Save changes to persistence
        saveItem()
    }
    
    // Delete completed subitems
    func deleteCompletedSubitems() {
        // Take snapshot before deletion
        let snapshot = item.subItems
        
        // Create a mutable copy of the item
        var mutableItem = item
        
        // Remove completed subitems
        let originalCount = mutableItem.subItems.count
        mutableItem.subItems.removeAll { $0.isCompleted }
        
        // Return early if nothing was deleted
        guard mutableItem.subItems.count < originalCount else { return }
        
        // Add to undo cache since something was deleted
        undoManager.addToUndoCache(.snapshot(items: snapshot))
        
        // Update the published item
        item = mutableItem
        
        // Save changes to persistence
        saveItem()
    }
    
    // Delete incomplete subitems
    func deleteIncompleteSubitems() {        
        // Take snapshot before deletion
        let snapshot = item.subItems
        
        // Create a mutable copy of the item
        var mutableItem = item
        
        // Remove incomplete subitems
        let originalCount = mutableItem.subItems.count
        mutableItem.subItems.removeAll { !$0.isCompleted }
        
        // Return early if nothing was deleted
        guard mutableItem.subItems.count < originalCount else { return }
        
        // Add to undo cache since something was deleted
        undoManager.addToUndoCache(.snapshot(items: snapshot))
        
        // Update the published item
        item = mutableItem
        
        // Save changes to persistence
        saveItem()
    }
    
    // Undo the last deletion operation
    func undo() {
        guard let action = undoManager.getNextAction() else { return }
        
        switch action {
        case .snapshot(let items):
            // Remove all current subitems
            var mutableItem = item
            mutableItem.subItems.removeAll()
            
            // Add the snapshots items back in their original order
            for item in items {
                mutableItem.subItems.append(item)
            }
            
            // Update the published item
            item = mutableItem
            
            // Save changes
            saveItem()
        }
    }
    
    // Check if undo is available
    var canUndo: Bool {
        undoManager.canUndo
    }
} 
