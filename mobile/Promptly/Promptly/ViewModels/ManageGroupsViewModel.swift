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
    }
    
    func loadGroups() {
        groupStore.loadGroups()
        self.groups = groupStore.groups
        // Reset any pending deletion state
        self.groupIdToRemove = nil
    }
    
    func addGroup() {
        guard !newGroupName.isEmpty else { return }
        _ = groupStore.createGroup(title: newGroupName)
        newGroupName = ""
        isAddingNewGroup = false
        self.groups = groupStore.groups
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
            // For each item in the group, update it to remove the group association
            let groupItems = group.getAllItems()
            
            for item in groupItems {
                // Load the checklist for this specific date
                if let checklist = persistence.loadChecklist(for: item.date) {
                    // Find the item with this ID and remove its group association
                    var updatedChecklist = checklist
                    if let index = updatedChecklist.items.firstIndex(where: { $0.id == item.id }) {
                        var updatedItem = updatedChecklist.items[index]
                        updatedItem.updateGroup(nil)
                        updatedChecklist.items[index] = updatedItem
                        persistence.saveChecklist(updatedChecklist)
                    }
                }
            }
            
            // Wait a brief moment to allow animation to complete
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            
            // Delete the group from storage
            groupStore.deleteGroup(group)
            groupToDelete = nil
            
            // Update the groups list after deletion
            await MainActor.run {
                self.groups = self.groupStore.groups
                self.groupIdToRemove = nil
                
                // If the deleted group was selected, deselect it
                if selectedGroup?.id == group.id {
                    selectedGroup = nil
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
            groupStore.clearItemsFromGroup(groupId: group.id)
            
            // Reload the groups to ensure we have the latest data
            loadGroups()
            
            // Update UI
            await MainActor.run {
                // Update the selected group reference
                if let updatedGroup = groups.first(where: { $0.id == group.id }) {
                    selectedGroup = updatedGroup
                }
                
                // Clear the local items array
                self.groupItems = []
            }
        }
    }
    
    func updateGroupName(_ newName: String) {
        guard !newName.isEmpty, let group = selectedGroup else { return }
        
        groupStore.updateGroupTitle(group, newTitle: newName)
        // Update the local state to reflect the change immediately
        currentGroupTitle = newName
        // Update the timestamp to trigger a refresh in observers
        groupStore.lastGroupUpdateTimestamp = Date()
        // Update local groups array
        self.groups = groupStore.groups
    }
    
    func updateGroupColor(red: Double, green: Double, blue: Double) {
        guard let group = selectedGroup else { return }
        
        groupStore.updateGroupColor(group, red: red, green: green, blue: blue)
        // Update local state
        selectedColorRed = red
        selectedColorGreen = green
        selectedColorBlue = blue
        selectedColorHasColor = true
        
        // Update the groups array to refresh the UI
        self.groups = groupStore.groups
        
        // If the selected group exists in the updated groups array, update it
        if let updatedGroup = groups.first(where: { $0.id == group.id }) {
            selectedGroup = updatedGroup
        }
    }
    
    func removeGroupColor() {
        guard let group = selectedGroup else { return }
        
        groupStore.removeGroupColor(group)
        // Update local state
        selectedColorRed = 0
        selectedColorGreen = 0
        selectedColorBlue = 0
        selectedColorHasColor = false
        
        // Update the groups array to refresh the UI
        self.groups = groupStore.groups
        
        // If the selected group exists in the updated groups array, update it
        if let updatedGroup = groups.first(where: { $0.id == group.id }) {
            selectedGroup = updatedGroup
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
} 
