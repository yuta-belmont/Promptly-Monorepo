import Foundation

extension Models {
    struct Checklist: Identifiable, Codable {
        let id: UUID
        let date: Date
        var items: [ChecklistItem]
        var notes: String
        
        init(id: UUID = UUID(), date: Date = Date(), items: [ChecklistItem] = [], notes: String = "") {
            self.id = id
            self.date = date
            self.items = items
            self.notes = notes
        }
        
        mutating func toggleItem(_ item: ChecklistItem) {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isCompleted.toggle()
            }
        }
        
        mutating func addItem(_ item: ChecklistItem) {
            items.append(item)
        }
        
        mutating func updateItem(_ item: ChecklistItem) {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = item
            }
        }
        
        mutating func deleteItems(at indexSet: IndexSet) {
            items.remove(atOffsets: indexSet)
        }
        
        mutating func moveItems(from source: IndexSet, to destination: Int) {
            items.move(fromOffsets: source, toOffset: destination)
        }
        
        mutating func updateNotes(_ newNotes: String) {
            // Ensure notes don't exceed 2000 characters
            notes = String(newNotes.prefix(2000))
        }
        
        // Efficiently remove all items at once
        mutating func removeAllItems() {
            items = []
        }
        
        // Efficiently remove all items that belong to a specific group
        mutating func removeAllItemsInGroup(groupId: UUID) {
            items.removeAll(where: { $0.groupId == groupId })
        }
    }
} 
