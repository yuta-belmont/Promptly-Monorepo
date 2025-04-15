import Foundation
import SwiftUI

@MainActor
final class ManageGroupsViewModel: ObservableObject {
    @Published var groups: [Models.ItemGroup] = []
    @Published var selectedGroup: Models.ItemGroup? = nil
    @Published var groupToDelete: Models.ItemGroup? = nil
    @Published var showingDeleteGroupAlert = false
    @Published var newGroupName = ""
    @Published var isAddingNewGroup = false
    
    // Flag to indicate if we should remove the item from the UI
    @Published var groupIdToRemove: UUID? = nil
    
    private let groupStore = GroupStore.shared
    private let persistence = ChecklistPersistence.shared
    
    init() {
        loadGroups()
        setupExternalNotificationObservers()
    }
    
    // Setup notification observers for external changes
    private func setupExternalNotificationObservers() {
        // Listen for group changes from ItemDetailsView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleItemGroupUpdated(_:)),
            name: NSNotification.Name("ItemGroupUpdated"),
            object: nil
        )
    }
    
    @objc private func handleItemGroupUpdated(_ notification: Notification) {
        if let itemId = notification.object as? UUID {
            // Reload groups to ensure we have the latest data
            loadGroups()
        }
    }
    
    func loadGroups() {
        groupStore.loadGroups { [weak self] in
            guard let self = self else { return }
            self.groups = self.groupStore.groups
            // Reset any pending deletion state
            self.groupIdToRemove = nil
        }
    }
    
    func addGroup() {
        guard !newGroupName.isEmpty else { return }
        
        // Create group through GroupStore
        _ = groupStore.createGroup(title: newGroupName) { [weak self] in
            guard let self = self else { return }
            
            // Update our local state directly from the store
            self.groups = self.groupStore.groups
            
            // Clear the input
            self.newGroupName = ""
        }
    }
    
    // Save any pending new group when the view is dismissed
    func saveNewGroupIfNeeded() {
        if isAddingNewGroup && !newGroupName.isEmpty {
            addGroup()
        }
    }
    
    // Updated method to confirm deletion with a group directly
    func confirmDeleteGroup(_ group: Models.ItemGroup) {
        groupToDelete = group
        showingDeleteGroupAlert = true
    }
    
    // Keep the original method for backward compatibility
    func confirmDeleteGroup(at index: Int) {
        if index < groups.count {
            groupToDelete = groups[index]
            showingDeleteGroupAlert = true
        }
    }
    
    // Cancel the delete operation
    func cancelDelete() {
        groupToDelete = nil
        groupIdToRemove = nil
    }
    
    func deleteGroupKeepItems() {
        guard let group = groupToDelete else { return }
        
        // Set the group ID to remove - this will trigger the animation in the view
        self.groupIdToRemove = group.id
        
        Task {
            // Get all items in the group
            let groupItems = group.getAllItems()
            
            // For each item, directly update its group association
            for var item in groupItems {
                // Update the item's group to nil
                item.updateGroup(nil)
                
                // Update the group store
                groupStore.removeItemFromGroup(itemId: item.id, groupId: group.id)
            }
            
            // Delete the group from storage
            groupStore.deleteGroup(group) { [weak self] in
                guard let self = self else { return }
                
                self.groupToDelete = nil
                
                // Update the groups list after deletion
                self.groups = self.groupStore.groups
                self.groupIdToRemove = nil
                
                // If the deleted group was selected, deselect it
                if self.selectedGroup?.id == group.id {
                    self.selectedGroup = nil
                }
            }
        }
    }
    
    // MARK: - Group Details Methods
    
    @Published var groupItems: [Models.ChecklistItem] = []
    @Published var isLoadingItems = true
    @Published var showingDeleteAllAlert = false
    @Published var showingEditNameAlert = false
    @Published var showingColorPicker = false
    @Published var editingGroupName = ""
    
    // Color properties
    @Published var selectedColorRed: Double = 0
    @Published var selectedColorGreen: Double = 0
    @Published var selectedColorBlue: Double = 0
    @Published var selectedColorHasColor: Bool = false
    @Published var currentGroupTitle: String = ""
    
    func selectGroup(_ group: Models.ItemGroup) {
        selectedGroup = group
        // Get the latest group data from the store to ensure we have the most up-to-date title
        if let updatedGroup = groupStore.getGroup(by: group.id) {
            currentGroupTitle = updatedGroup.title
            selectedColorRed = updatedGroup.colorRed
            selectedColorGreen = updatedGroup.colorGreen
            selectedColorBlue = updatedGroup.colorBlue
            selectedColorHasColor = updatedGroup.hasColor
        } else {
            // Fall back to the provided group if not found in the store
            currentGroupTitle = group.title
            selectedColorRed = group.colorRed
            selectedColorGreen = group.colorGreen
            selectedColorBlue = group.colorBlue
            selectedColorHasColor = group.hasColor
        }
        loadItems()
    }
    
    func loadItems() {
        guard let group = selectedGroup else { return }
        isLoadingItems = true
        
        Task {
            // Get the latest group data from the store to ensure we have the most up-to-date items
            if let updatedGroup = groupStore.getGroup(by: group.id) {
                // Get all items from the updated group
                let loadedItems = updatedGroup.getAllItems()
                
                await MainActor.run {
                    self.groupItems = loadedItems
                    self.isLoadingItems = false
                }
            } else {
                // Fallback to the original group if for some reason it's not in the store
                let loadedItems = group.getAllItems()
                
                await MainActor.run {
                    self.groupItems = loadedItems
                    self.isLoadingItems = false
                }
            }
        }
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
                
                // Reload the groups to ensure we have the latest data
                self.loadGroups()
                
                // Update UI
                // Update the selected group reference
                if let updatedGroup = self.groups.first(where: { $0.id == group.id }) {
                    self.selectedGroup = updatedGroup
                }
                
                // Clear the local items array
                self.groupItems = []
            }
        }
    }
    
    func updateGroupName(_ group: Models.ItemGroup, newName: String) {
        guard !newName.isEmpty else { return }
        
        // Update in GroupStore directly
        groupStore.updateGroupTitle(group, newTitle: newName) { [weak self] in
            guard let self = self else { return }
            
            // Update our local state from the store
            self.groups = self.groupStore.groups
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
            
            // Update the groups array to refresh the UI
            self.groups = self.groupStore.groups
            
            // If the selected group exists in the updated groups array, update it
            if let updatedGroup = self.groups.first(where: { $0.id == group.id }) {
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
            
            // Update the groups array to refresh the UI
            self.groups = self.groupStore.groups
            
            // If the selected group exists in the updated groups array, update it
            if let updatedGroup = self.groups.first(where: { $0.id == group.id }) {
                self.selectedGroup = updatedGroup
            }
        }
    }
    
    func deleteGroupKeepItemsAndDeselectGroup() {
        guard let group = selectedGroup else { return }
        
        Task {
            // For each item, update it to remove the group association
            for item in groupItems {
                if let checklist = persistence.loadChecklist(for: item.date) {
                    var updatedChecklist = checklist
                    if let index = updatedChecklist.items.firstIndex(where: { $0.id == item.id }) {
                        var updatedItem = updatedChecklist.items[index]
                        updatedItem.updateGroup(nil)
                        updatedChecklist.items[index] = updatedItem
                        persistence.saveChecklist(updatedChecklist)
                    }
                }
            }
            
            // Delete the group
            groupStore.deleteGroup(group)
            
            // Update local groups array
            self.groups = groupStore.groups
            
            // Deselect the group
            await MainActor.run {
                selectedGroup = nil
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
                    
                    // Reload the groups to ensure we have the latest data
                    self.loadGroups()
                    
                    // Update UI
                    // Update the selected group reference
                    if let updatedGroup = self.groups.first(where: { $0.id == group.id }) {
                        self.selectedGroup = updatedGroup
                    }
                    
                    // Update the groupItems array by removing the item
                    if let itemIndex = self.groupItems.firstIndex(where: { $0.id == item.id }) {
                        self.groupItems.remove(at: itemIndex)
                    }
                    
                    // Notify that the item was removed from the group
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ItemRemovedFromGroup"),
                        object: item.id
                    )
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
                    
                    // Reload the groups to ensure we have the latest data
                    self.loadGroups()
                    
                    // Update UI
                    // Update the selected group reference
                    if let group = self.selectedGroup {
                        if let updatedGroup = self.groups.first(where: { $0.id == group.id }) {
                            self.selectedGroup = updatedGroup
                        }
                    }
                    
                    // Update the groupItems array by removing the item
                    if let itemIndex = self.groupItems.firstIndex(where: { $0.id == item.id }) {
                        self.groupItems.remove(at: itemIndex)
                    }
                    
                    // Notify that the item was deleted
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ItemDeleted"),
                        object: item.id
                    )
                }
            }
        }
    }
    
    // MARK: - Group Management
    
    func reorderGroups(from sourceIndex: Int, to destinationIndex: Int) {
        // Adjust destination index based on move direction
        let adjustedDestinationIndex = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        
        // Create a new array with the group moved in a single operation
        var newGroups = groups
        let groupToMove = newGroups.remove(at: sourceIndex)
        newGroups.insert(groupToMove, at: adjustedDestinationIndex)
        
        // Update the groups array atomically
        groups = newGroups
        
        // Then update store
        groupStore.reorderGroups(from: sourceIndex, to: adjustedDestinationIndex) { [weak self] in
            guard let self = self else { return }
        }
    }
    
    func removeGroup() {
        guard let groupId = groupIdToRemove,
              let group = groups.first(where: { $0.id == groupId }) else { return }
        
        // Delete from GroupStore directly
        groupStore.deleteGroup(group) { [weak self] in
            guard let self = self else { return }
            
            // Update our local state directly
            if let index = self.groups.firstIndex(where: { $0.id == groupId }) {
                self.groups.remove(at: index)
            }
            
            // Clear the group to remove
            self.groupIdToRemove = nil
        }
    }
} 
