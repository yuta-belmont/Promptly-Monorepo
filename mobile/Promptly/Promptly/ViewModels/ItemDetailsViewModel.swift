import Foundation
import SwiftUI
import Combine

// Add debug helper function at the top
private func debugLog(_ source: String, _ action: String) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    print("\(timestamp) [ItemDetailsViewModel]: \(source) - \(action)")
}

@MainActor
final class ItemDetailsViewModel: ObservableObject {
    @Published var item: Models.ChecklistItem
    @Published var isLoading: Bool = false
    
    private let persistence = ChecklistPersistence.shared
    private let notificationManager = NotificationManager.shared
    let groupStore = GroupStore.shared
    private var cancellables = Set<AnyCancellable>()
    
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
    func addSubitem(_ title: String) {
        debugLog("addSubitem", "called with title: \(title)")
        // Create a new subitem
        let newSubitem = Models.SubItem(
            id: UUID(),
            title: title,
            isCompleted: false
        )
        
        // Directly add the subitem to the item's collection
        item.addSubItem(newSubitem)
        
        // If the parent item was previously completed, mark it incomplete
        // since we've added a new incomplete subitem
        if item.isCompleted {
            item.isCompleted = false
        }
        
        // Save to persistence
        saveItem()
    }
    
    // Public method to save changes when view disappears
    func saveChanges() {
        debugLog("saveChanges", "saving item state on view disappear")
        saveItem()
    }
    
    // Save the updated item to persistence
    private func saveItem() {
        debugLog("saveItem", "called")
        // Load the current checklist for the item's date
        guard var checklist = persistence.loadChecklist(for: item.date) else {
            debugLog("saveItem", "no existing checklist found, creating new")
            // If no checklist exists for this date, create a new one
            var newChecklist = Models.Checklist(date: item.date)
            newChecklist.addItem(item)
            persistence.saveChecklist(newChecklist)
            return
        }
        
        debugLog("saveItem", "updating item in existing checklist")
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
        
        // Notify the app that the checklist was updated
        NotificationCenter.default.post(
            name: Notification.Name("NewChecklistAvailable"),
            object: item.date
        )
    }
    
    // Helper method to load fresh item data during initialization
    private func loadFreshItemData() async {
        await MainActor.run {
            // Get the latest checklist for the item's date
            if let checklist = persistence.loadChecklist(for: item.date),
               let freshItem = checklist.items.first(where: { $0.id == item.id }) {
                // Update our item with the fresh data if found
                self.item = freshItem
                debugLog("loadFreshItemData", "loaded fresh item during initialization")
            } else {
                debugLog("loadFreshItemData", "no fresh item found during initialization, keeping passed item")
            }
        }
    }
    
    // Load the latest version of the item from persistence
    func loadDetails() {
        debugLog("loadDetails", "called for item ID: \(item.id.uuidString.prefix(8))")
        isLoading = true
        
        // Get the latest checklist for the item's date
        if let checklist = persistence.loadChecklist(for: item.date) {
            // Find the latest version of the item in the checklist
            if let freshItem = checklist.items.first(where: { $0.id == item.id }) {
                debugLog("loadDetails", "found fresh item with group ID: \(String(describing: freshItem.groupId?.uuidString.prefix(8)))")
                
                // Update the item with the latest data
                self.item = freshItem
            } else {
                debugLog("loadDetails", "item not found in checklist, keeping current version")
            }
        }
        
        // Mark loading as complete
        isLoading = false
    }
    
    // MARK: - PopoverContentView Support Methods
    
    // Update notification for the item
    func updateNotification(_ newNotification: Date?) {
        debugLog("updateNotification", "called with date: \(String(describing: newNotification))")
        
        // Cancel existing notification if there is one
        if let oldNotification = item.notification {
            // Use the correct method to remove notifications
            notificationManager.removeAllNotificationsForItem(item)
        }
        
        // Update the item with the new notification date
        var mutableItem = item
        mutableItem.notification = newNotification
        item = mutableItem
        
        // Schedule new notification if needed
        if let newDate = newNotification {
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
        debugLog("updateGroup", "called with group ID: \(String(describing: newGroupId?.uuidString.prefix(8)))")
        
        // Create a mutable copy of the item
        var mutableItem = item
        
        if let newGroupId = newGroupId {
            // Get the group from the GroupStore
            if let group = groupStore.getGroup(by: newGroupId) {
                // Use the updateGroup method to set the group reference
                mutableItem.updateGroup(group)
                debugLog("updateGroup", "set group: \(group.title)")
            } else {
                // Group not found, clear the group
                mutableItem.updateGroup(nil)
                debugLog("updateGroup", "group not found, setting to nil")
            }
        } else {
            // Clear the group if newGroupId is nil
            mutableItem.updateGroup(nil)
            debugLog("updateGroup", "clearing group (nil)")
        }
        
        // Update the published item
        item = mutableItem
        
        // Save changes to persistence
        saveItem()
    }
    
    // Toggle the completed state of the item
    func toggleCompleted() {
        debugLog("toggleCompleted", "toggling isCompleted from \(item.isCompleted) to \(!item.isCompleted)")
        
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
        
        // Save changes to persistence
        saveItem()
    }
    
    // Toggle the completion state of a subitem
    func toggleSubitemCompleted(subitemId: UUID) {
        debugLog("toggleSubitemCompleted", "toggling subitem with ID: \(subitemId.uuidString.prefix(8))")
        
        // Create a mutable copy of the item
        var mutableItem = item
        
        // Find the subitem and toggle its completion state
        if let subitemIndex = mutableItem.subItems.firstIndex(where: { $0.id == subitemId }) {
            mutableItem.subItems[subitemIndex].isCompleted.toggle()
            
            // Update the published item
            item = mutableItem
            
            // Save changes to persistence
            saveItem()
        }
    }
} 
