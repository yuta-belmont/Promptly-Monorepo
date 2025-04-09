import Foundation
import SwiftUI

@MainActor
final class GroupDetailsViewModel: ObservableObject {
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
    
    private let groupStore = GroupStore.shared
    private let persistence = ChecklistPersistence.shared
    var selectedGroup: Models.ItemGroup?
    
    func setSelectedGroup(_ group: Models.ItemGroup) {
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
                
                // Clear the local items array
                self.groupItems = []
            }
        }
    }
    
    func updateGroupName(_ newName: String) {
        guard !newName.isEmpty, let group = selectedGroup else { return }
        
        groupStore.updateGroupTitle(group, newTitle: newName) { [weak self] in
            guard let self = self else { return }
            // Update the local state to reflect the change immediately
            self.currentGroupTitle = newName
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
        
        return PlannerItemDisplayData.from(item: item, groupsCache: groupsCache)
    }
    
    /// Gets display data for all items
    func getAllDisplayData() -> [PlannerItemDisplayData] {
        return groupItems.map { getDisplayData(for: $0) }
    }
} 