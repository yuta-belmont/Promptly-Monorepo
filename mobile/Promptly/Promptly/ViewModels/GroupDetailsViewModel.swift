import Foundation
import SwiftUI

@MainActor
final class GroupDetailsViewModel: ObservableObject {
    @Published var groupItems: [Models.ChecklistItem] = []
    @Published var isLoadingItems = true
    @Published var showingDeleteAllAlert = false
    @Published var showingEditNameAlert = false
    @Published var showingColorPicker = false
    @Published var showingRemoveAllAlert = false
    @Published var editingGroupName = ""
    
    // Color properties
    @Published var selectedColorRed: Double = 0
    @Published var selectedColorGreen: Double = 0
    @Published var selectedColorBlue: Double = 0
    @Published var selectedColorHasColor: Bool = false
    @Published var currentGroupTitle: String = ""
    @Published var selectedGroup: Models.ItemGroup?
    
    // For item expansion state
    @Published private var expandedItemIds: Set<UUID> = []
    
    private let groupStore = GroupStore.shared
    private let persistence = ChecklistPersistence.shared
    private let notificationManager = NotificationManager.shared
    
    // MARK: - Initialization and Setup
    
    func setSelectedGroup(_ group: Models.ItemGroup) {
        // Get the latest group data from the store to ensure we have the most up-to-date title
        if let updatedGroup = groupStore.getGroup(by: group.id) {
            selectedGroup = updatedGroup
            currentGroupTitle = updatedGroup.title
            selectedColorRed = updatedGroup.colorRed
            selectedColorGreen = updatedGroup.colorGreen
            selectedColorBlue = updatedGroup.colorBlue
            selectedColorHasColor = updatedGroup.hasColor
        } else {
            // Fall back to the provided group if not found in the store
            selectedGroup = group
            currentGroupTitle = group.title
            selectedColorRed = group.colorRed
            selectedColorGreen = group.colorGreen
            selectedColorBlue = group.colorBlue
            selectedColorHasColor = group.hasColor
        }
        loadItems()
        
        // Listen for global item deletion notifications (from other views)
        setupExternalNotificationObservers()
    }
    
    // Setup notification observers for external changes only
    private func setupExternalNotificationObservers() {
        // Only observe notifications that come from outside this view
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalItemDeleted(_:)),
            name: NSNotification.Name("ItemDeleted"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalGroupUpdates(_:)),
            name: NSNotification.Name("GroupUpdated"),
            object: nil
        )
        
        // Listen for ItemDetailsUpdated notifications from ItemDetailsView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleItemDetailsUpdated(_:)),
            name: NSNotification.Name("ItemDetailsUpdated"),
            object: nil
        )
        
        // Listen for group changes from ItemDetailsView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleItemGroupUpdated(_:)),
            name: NSNotification.Name("ItemGroupUpdated"),
            object: nil
        )
    }
    
    @objc private func handleExternalItemDeleted(_ notification: Notification) {
        if let itemId = notification.object as? UUID {
            // Only reload if the deleted item was in our group
            if groupItems.contains(where: { $0.id == itemId }) {
                loadItems()
            }
        }
    }
    
    @objc private func handleExternalGroupUpdates(_ notification: Notification) {
        if let groupId = notification.object as? UUID, 
           groupId == selectedGroup?.id {
            // Only reload if it's our group that was updated externally
            loadItems()
        }
    }
    
    @objc private func handleItemDetailsUpdated(_ notification: Notification) {
        if let updatedItemId = notification.object as? UUID {
            // Check if the updated item is in our group
            if groupItems.contains(where: { $0.id == updatedItemId }) {
                // Update just this specific item with fresh data from persistence
                updateSingleItem(with: updatedItemId)
                
                // Check and update the item's expanded state
                if let item = groupItems.first(where: { $0.id == updatedItemId }) {
                    // If the item has no subitems but is in the expanded set, remove it
                    if item.subItems.isEmpty && expandedItemIds.contains(updatedItemId) {
                        expandedItemIds.remove(updatedItemId)
                        objectWillChange.send()
                    }
                }
            }
        }
    }
    
    @objc private func handleItemGroupUpdated(_ notification: Notification) {
        if let itemId = notification.object as? UUID {
            // First, update the group store
            groupStore.loadGroups { [weak self] in
                guard let self = self else { return }
                
                // Update the selectedGroup with the latest data
                if let group = self.selectedGroup {
                    if let updatedGroup = self.groupStore.getGroup(by: group.id) {
                        self.selectedGroup = updatedGroup
                    }
                }
                
                // Update the groupItems array by removing the item locally
                if let itemIndex = self.groupItems.firstIndex(where: { $0.id == itemId }) {
                    self.groupItems.remove(at: itemIndex)
                }
                
                // Notify other views of group structure change
                NotificationCenter.default.post(
                    name: NSNotification.Name("ItemRemovedFromGroup"),
                    object: itemId
                )
            }
        }
    }
    
    // Update a single item in groupItems instead of reloading all items
    private func updateSingleItem(with itemId: UUID) {
        // Find the matching item
        guard let itemIndex = groupItems.firstIndex(where: { $0.id == itemId }) else { return }
        
        // Get the date of the item so we can load the right checklist
        let itemDate = groupItems[itemIndex].date
        
        // Debug: Print the current item state in ViewModel
        
        // Load only the checklist for this specific item's date
        if let checklist = persistence.loadChecklist(for: itemDate) {
            // Find the updated item in the checklist
            if let updatedItem = checklist.items.first(where: { $0.id == itemId }) {
                // Debug: Print the updated item from persistence
                
                // Replace the item in our local array with the fresh data
                groupItems[itemIndex] = updatedItem
                
                // Ensure lastModified is updated to force an ID change in the view
                groupItems[itemIndex].lastModified = Date()
                
                // Notify SwiftUI to update the view
                objectWillChange.send()
            }
        }
    }
    
    func loadItems() {
        guard let group = selectedGroup else { return }
        isLoadingItems = true
        
        Task {
            // Get the latest group data from the store to ensure we have the most up-to-date items
            let updatedGroup = groupStore.getGroup(by: group.id) ?? group
            
            // Get all item references from the group
            let itemReferences = updatedGroup.getAllItems()
            
            // Extract just the IDs from the references
            let itemIds = itemReferences.map { $0.id }
            
            // Directly fetch the latest version of each item by ID from persistence
            let freshItems = persistence.loadItemsByIds(itemIds)
            
            await MainActor.run {
                self.groupItems = freshItems
                self.isLoadingItems = false
            }
        }
    }
    
    // MARK: - Item Management
    
    // Toggle completion state of an item
    func toggleItemCompletion(itemId: UUID, notification: Date?) {
        guard let index = groupItems.firstIndex(where: { $0.id == itemId }) else { return }
        
        // Toggle completion state locally and update lastModified for proper state refresh
        groupItems[index].isCompleted.toggle()
        groupItems[index].lastModified = Date() // Update timestamp to force data changes to propagate
        
        // Update in persistence
        if var checklist = persistence.loadChecklist(for: groupItems[index].date) {
            if let checklistIndex = checklist.items.firstIndex(where: { $0.id == itemId }) {
                // Update both completion status and lastModified in the persisted item
                checklist.items[checklistIndex].isCompleted.toggle()
                checklist.items[checklistIndex].lastModified = Date()
                
                // Save to persistence
                persistence.saveChecklist(checklist)
                
                // Handle notification if needed
                if let notification = notification, !groupItems[index].isCompleted {
                    // Reschedule notification if item was marked incomplete
                    notificationManager.scheduleNotification(for: groupItems[index], in: checklist)
                } else if groupItems[index].isCompleted {
                    // Remove notification if item was marked complete
                    notificationManager.removeAllNotificationsForItem(groupItems[index])
                }
            }
        }
        
        // Notify the UI to update
        objectWillChange.send()
    }

    // Toggle sub-item completion
    func toggleSubItemCompletion(mainItemId: UUID, subItemId: UUID, isCompleted: Bool) {
        guard let mainIndex = groupItems.firstIndex(where: { $0.id == mainItemId }) else { return }
        
        // Update locally and set lastModified
        if let localSubItemIndex = groupItems[mainIndex].subItems.firstIndex(where: { $0.id == subItemId }) {
            groupItems[mainIndex].subItems[localSubItemIndex].isCompleted = isCompleted
            groupItems[mainIndex].lastModified = Date() // Update parent's lastModified to trigger UI refresh
        }
        
        // Update in persistence
        if var checklist = persistence.loadChecklist(for: groupItems[mainIndex].date) {
            if let checklistIndex = checklist.items.firstIndex(where: { $0.id == mainItemId }) {
                if let subItemIndex = checklist.items[checklistIndex].subItems.firstIndex(where: { $0.id == subItemId }) {
                    // Update in persistence
                    checklist.items[checklistIndex].subItems[subItemIndex].isCompleted = isCompleted
                    checklist.items[checklistIndex].lastModified = Date() // Update parent's lastModified
                    persistence.saveChecklist(checklist)
                }
            }
        }
        
        // Notify the UI to update
        objectWillChange.send()
    }

    // Update notification
    func updateItemNotification(itemId: UUID, notification: Date?) {
        guard let index = groupItems.firstIndex(where: { $0.id == itemId }) else { return }
        
        // Update locally first for immediate UI feedback
        groupItems[index].notification = notification
        
        // Update in persistence
        if var checklist = persistence.loadChecklist(for: groupItems[index].date) {
            if let checklistIndex = checklist.items.firstIndex(where: { $0.id == itemId }) {
                checklist.items[checklistIndex].notification = notification
                
                // Update notification manager
                let item = checklist.items[checklistIndex]
                notificationManager.updateNotificationForEditedItem(item, in: checklist)
                
                persistence.saveChecklist(checklist)
            }
        }
        
        // No notifications - rely on SwiftUI's natural binding for UI updates
    }
    
    // Toggle item expansion
    func toggleItemExpanded(_ itemId: UUID) {
        if expandedItemIds.contains(itemId) {
            expandedItemIds.remove(itemId)
        } else {
            // Only add if item has subitems
            if let item = groupItems.first(where: { $0.id == itemId }), !item.subItems.isEmpty {
                expandedItemIds.insert(itemId)
            }
        }
        objectWillChange.send()
    }
    
    func deleteAllItems() {
        guard let group = selectedGroup else { return }
        
        Task {
            // Get all unique dates that have items from this group
            let uniqueDates = Set(groupItems.map { $0.date })
            
            // For each unique date, efficiently remove all items from that group
            for date in uniqueDates {
                if let checklist = persistence.loadChecklist(for: date) {
                    var updatedChecklist = checklist
                    updatedChecklist.removeAllItemsInGroup(groupId: group.id)
                    persistence.saveChecklist(updatedChecklist)
                }
            }
            
            // Clear the group's items in the group store
            groupStore.clearItemsFromGroup(groupId: group.id) { [weak self] in
                guard let self = self else { return }
                
                // Clear the local items array directly
                self.groupItems = []
                
                // Notify other views that may be showing these items
                NotificationCenter.default.post(
                    name: NSNotification.Name("GroupItemsDeleted"),
                    object: group.id
                )
            }
        }
    }
    
    func removeAllItemsFromGroup() {
        guard let group = selectedGroup else { return }
        
        Task {
            // Get all unique dates that have items from this group
            let uniqueDates = Set(groupItems.map { $0.date })
            
            // For each unique date, remove group association from items
            for date in uniqueDates {
                if let checklist = persistence.loadChecklist(for: date) {
                    var updatedChecklist = checklist
                    // Remove group association from all items in this group
                    for (index, item) in updatedChecklist.items.enumerated() {
                        if item.groupId == group.id {
                            var updatedItem = item
                            updatedItem.updateGroup(nil)
                            updatedChecklist.items[index] = updatedItem
                        }
                    }
                    persistence.saveChecklist(updatedChecklist)
                }
            }
            
            // Clear the group's items in the group store
            groupStore.clearItemsFromGroup(groupId: group.id) { [weak self] in
                guard let self = self else { return }
                
                // Clear the local items array directly
                self.groupItems = []
                
                // Notify other views that may be showing these items
                NotificationCenter.default.post(
                    name: NSNotification.Name("GroupItemsRemoved"),
                    object: group.id
                )
            }
        }
    }
    
    func updateGroupName(_ newName: String) {
        guard !newName.isEmpty, let group = selectedGroup else { return }
        
        groupStore.updateGroupTitle(group, newTitle: newName) { [weak self] in
            guard let self = self else { return }
            // Update the local state to reflect the change immediately
            self.currentGroupTitle = newName
            
            // Update the selectedGroup with the new name
            if let updatedGroup = groupStore.getGroup(by: group.id) {
                self.selectedGroup = updatedGroup
            }
        }
    }
    
    func updateGroupColor(red: Double, green: Double, blue: Double) {
        guard let group = selectedGroup else { return }
        
        groupStore.updateGroupColor(group, red: red, green: green, blue: blue) { [weak self] in
            guard let self = self else { return }
            // Update local state
            self.selectedColorRed = red
            self.selectedColorGreen = green
            self.selectedColorBlue = blue
            self.selectedColorHasColor = true
            
            // Get the updated group from the store
            if let updatedGroup = groupStore.getGroup(by: group.id) {
                self.selectedGroup = updatedGroup
            }
        }
    }
    
    func removeGroupColor() {
        guard let group = selectedGroup else { return }
        
        groupStore.removeGroupColor(group) { [weak self] in
            guard let self = self else { return }
            // Update local state
            self.selectedColorRed = 0
            self.selectedColorGreen = 0
            self.selectedColorBlue = 0
            self.selectedColorHasColor = false
            
            // Get the updated group from the store
            if let updatedGroup = groupStore.getGroup(by: group.id) {
                self.selectedGroup = updatedGroup
            }
        }
    }
    
    func updateGroupNotes(_ newNotes: String) {
        guard let group = selectedGroup else { return }
        
        // Create a new group with updated notes
        var updatedGroup = group
        updatedGroup.updateNotes(newNotes)
        
        // Update in the group store
        groupStore.updateGroupNotes(group, newNotes: newNotes) { [weak self] in
            guard let self = self else { return }
            // Update the selectedGroup with the new notes
            if let updatedGroup = groupStore.getGroup(by: group.id) {
                self.selectedGroup = updatedGroup
            }
        }
    }
    
    func removeItemFromGroup(_ item: Models.ChecklistItem, group: Models.ItemGroup) {
        // Load the checklist for this specific date
        if let checklist = persistence.loadChecklist(for: item.date) {
            // Find the item with this ID and remove its group association
            var updatedChecklist = checklist
            if let index = updatedChecklist.items.firstIndex(where: { $0.id == item.id }) {
                var updatedItem = updatedChecklist.items[index]
                updatedItem.updateGroup(nil)
                updatedChecklist.items[index] = updatedItem
                persistence.saveChecklist(updatedChecklist)
                
                // Update the group store
                groupStore.removeItemFromGroup(itemId: item.id, groupId: group.id) { [weak self] in
                    guard let self = self else { return }
                    
                    // Reload groups to ensure we have the latest data
                    self.groupStore.loadGroups { [weak self] in
                        guard let self = self else { return }
                        
                        // Update the selectedGroup with the latest data
                        if let updatedGroup = self.groupStore.getGroup(by: group.id) {
                            self.selectedGroup = updatedGroup
                        }
                        
                        // Update the groupItems array by removing the item locally
                        if let itemIndex = self.groupItems.firstIndex(where: { $0.id == item.id }) {
                            self.groupItems.remove(at: itemIndex)
                        }
                        
                        // Notify other views of group structure change
                        NotificationCenter.default.post(
                            name: NSNotification.Name("ItemRemovedFromGroup"),
                            object: item.id
                        )
                    }
                }
            }
        }
    }
    
    func deleteItem(_ item: Models.ChecklistItem) {
        // Load the checklist for this specific date
        if let checklist = persistence.loadChecklist(for: item.date) {
            // Find and remove the item
            var updatedChecklist = checklist
            if let index = updatedChecklist.items.firstIndex(where: { $0.id == item.id }) {
                updatedChecklist.items.remove(at: index)
                persistence.saveChecklist(updatedChecklist)
                
                // Update the group store
                groupStore.removeItemFromAllGroups(itemId: item.id) { [weak self] in
                    guard let self = self else { return }
                    
                    // Update the groupItems array by removing the item locally first
                    if let itemIndex = self.groupItems.firstIndex(where: { $0.id == item.id }) {
                        self.groupItems.remove(at: itemIndex)
                    }
                    
                    // Notify other views that this item was deleted
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ItemDeleted"),
                        object: item.id
                    )
                }
            }
        }
    }
    
    // MARK: - Display Data
    
    /// Converts a ChecklistItem to a PlannerItemDisplayData for UI rendering
    func getDisplayData(for item: Models.ChecklistItem) -> PlannerItemDisplayData {
        // Create a groups cache with just the current group
        let groupsCache: [UUID: GroupInfo] = {
            guard let group = selectedGroup else { return [:] }
            let groupInfo = GroupInfo(
                title: group.title,
                color: group.hasColor ? Color(red: group.colorRed, green: group.colorGreen, blue: group.colorBlue) : nil
            )
            return [group.id: groupInfo]
        }()
        
        return PlannerItemDisplayData.from(
            item: item, 
            groupsCache: groupsCache,
            expandedItems: expandedItemIds
        )
    }
    
    /// Gets display data for all items
    func getAllDisplayData() -> [PlannerItemDisplayData] {
        return groupItems.map { getDisplayData(for: $0) }
    }
} 
