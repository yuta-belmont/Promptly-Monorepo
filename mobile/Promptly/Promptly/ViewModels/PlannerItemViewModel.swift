import Foundation
import SwiftUI
import Combine

@MainActor
final class PlannerItemViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var item: Models.ChecklistItem
    @Published var text: String
    @Published var isEditing: Bool = false
    @Published var isDeleting: Bool = false
    @Published var showingPopover: Bool = false
    @Published var opacity: Double = 1.0
    @Published var isGroupSectionExpanded: Bool = false
    @Published var areSubItemsExpanded: Bool = false
    @Published var newSubItemText: String = ""
    
    // MARK: - Private Properties
    private let persistence = ChecklistPersistence.shared
    private let notificationManager = NotificationManager.shared
    private let groupStore = GroupStore.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(item: Models.ChecklistItem) {
        self.item = item
        self.text = item.title
        // If the item has subitems, default to collapsed state
        self.areSubItemsExpanded = false
        
        // Set up binding between text field and item title
        $text
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] newValue in
                self?.updateItemTitle(newValue)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Item Management
    
    /// Updates the item's title and saves it if needed
    func updateItemTitle(_ newTitle: String) {
        if item.title != newTitle {
            var updatedItem = item
            updatedItem.title = newTitle
            updateItem(updatedItem)
        }
    }
    
    /// Toggles completion state of the item
    func toggleItem() {
        var updatedItem = item
        updatedItem.isCompleted.toggle()
        updateItem(updatedItem)
    }
    
    /// Updates the notification time for the item
    func updateNotification(_ date: Date?) {
        var updatedItem = item
        updatedItem.notification = date
        
        // Reset completion status if a notification is being set
        if date != nil {
            updatedItem.isCompleted = false
        }
        
        updateItem(updatedItem)
    }
    
    /// Updates the group association for the item
    func updateGroup(_ groupId: UUID?) {
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
        
        updateItem(updatedItem)
    }
    
    // MARK: - SubItem Management
    
    /// Adds a new subitem to the item
    func addSubItem(_ title: String) {
        // Create a new empty subitem if no title is provided
        let subItemTitle = title.isEmpty ? "" : title
        
        // Make all changes to a local copy before updating the published property
        var updatedItem = item
        
        // Create and add the new subitem
        let newSubItem = Models.SubItem(
            id: UUID(),
            title: subItemTitle,
            isCompleted: false
        )
        
        updatedItem.subItems.append(newSubItem)
        
        // Adding a new incomplete subitem might need to change the parent item's completion status
        // If the parent was previously complete, it should now be incomplete since we've added an incomplete subitem
        if updatedItem.isCompleted && !updatedItem.subItems.allSatisfy({ $0.isCompleted }) {
            updatedItem.isCompleted = false
        }
        
        // Make a single update to the published property to minimize UI redraws
        self.item = updatedItem
        saveItem()
        
        // No need to animate expansion here - handled by the view
    }
    
    /// Toggles completion state of a subitem
    func toggleSubItem(_ subItemId: UUID) {
        guard let index = item.subItems.firstIndex(where: { $0.id == subItemId }) else { return }
        
        var updatedItem = item
        var updatedSubItem = updatedItem.subItems[index]
        updatedSubItem.isCompleted.toggle()
        updatedItem.subItems[index] = updatedSubItem
        
        updateItem(updatedItem)
    }
    
    /// Updates the text of a subitem
    func updateSubItemText(_ subItemId: UUID, newText: String) {
        guard let index = item.subItems.firstIndex(where: { $0.id == subItemId }) else { return }
        
        // If text is empty, delete the subitem
        if newText.isEmpty {
            deleteSubItem(subItemId)
            return
        }
        
        var updatedItem = item
        var updatedSubItem = updatedItem.subItems[index]
        updatedSubItem.title = newText
        updatedItem.subItems[index] = updatedSubItem
        
        updateItem(updatedItem)
    }
    
    /// Deletes a subitem
    func deleteSubItem(_ subItemId: UUID) {
        var updatedItem = item
        updatedItem.subItems.removeAll { $0.id == subItemId }
        updateItem(updatedItem)
    }
    
    // MARK: - UI State Management
    
    /// Handle starting the delete animation
    func startDeletingAnimation() {
        isDeleting = true
        withAnimation(.easeOut(duration: 0.25)) {
            opacity = 0.1
        }
    }
    
    /// Formats notification time for display
    func formatNotificationTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    /// Determines if the group color should be displayed
    var groupColor: Color? {
        // Use the direct group reference if available
        if let group = item.group, group.hasColor {
            return Color(red: group.colorRed, green: group.colorGreen, blue: group.colorBlue)
        }
        
        // Fallback to looking up by ID for backward compatibility
        guard let groupId = item.groupId,
              let group = groupStore.getGroup(by: groupId) else {
            return nil
        }
        
        // Use the direct color properties and hasColor flag
        if group.hasColor {
            return Color(red: group.colorRed, green: group.colorGreen, blue: group.colorBlue)
        } else {
            return nil
        }
    }
    
    // MARK: - Helper Methods
    
    /// Updates the item and saves changes
    private func updateItem(_ updatedItem: Models.ChecklistItem) {
        self.item = updatedItem
        saveItem()
    }
    
    /// Gets a group by ID
    func getGroup(by groupId: UUID) -> Models.ItemGroup? {
        return groupStore.getGroup(by: groupId)
    }
    
    /// Checks if an item has a valid group
    func hasValidGroup() -> Bool {
        return item.group != nil || (item.groupId != nil && groupStore.getGroup(by: item.groupId!) != nil)
    }
    
    /// Gets the title of the item's group
    func getGroupTitle() -> String? {
        if let group = item.group {
            return group.title
        } else if let groupId = item.groupId, let group = groupStore.getGroup(by: groupId) {
            return group.title
        }
        return nil
    }
    
    /// Saves the item to persistence
    private func saveItem() {
        // Load the current checklist for the item's date
        guard var checklist = persistence.loadChecklist(for: item.date) else {
            // If no checklist exists for this date, create a new one
            var newChecklist = Models.Checklist(date: item.date)
            newChecklist.addItem(item)
            persistence.saveChecklist(newChecklist)
            return
        }
        
        // Update the item in the checklist
        checklist.updateItem(item)
        
        // Update notifications if needed
        if let notification = item.notification, !item.isCompleted {
            notificationManager.updateNotificationForEditedItem(item, in: checklist)
        } else {
            notificationManager.removeAllNotificationsForItem(item)
        }
        
        // Save the updated checklist
        persistence.saveChecklist(checklist)
    }
    
    // MARK: - Public Save Method
    /// Saves the current state of the item and its subitems to persistence
    func save() {
        saveItem()
    }
} 
