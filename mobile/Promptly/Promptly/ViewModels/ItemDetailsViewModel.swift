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
    
    // Placeholder for future functionality
    func loadDetails() {
        // This will be expanded later to load additional details if needed
        isLoading = true
        
        // Simulate loading for now
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isLoading = false
        }
    }
} 