import Foundation

// Reference type collection to hold ChecklistItems
class ItemCollection {
    var items: [Models.ChecklistItem]
    
    init(items: [Models.ChecklistItem] = []) {
        self.items = items
    }
}

extension Models {
    struct Checklist: Identifiable, Codable {
        let id: UUID
        let date: Date
        var itemCollection: ItemCollection
        var notes: String
        var isEdited: Bool
        
        // Computed property to maintain backward compatibility
        var items: [ChecklistItem] {
            get { return itemCollection.items }
            set { itemCollection.items = newValue }
        }
        
        // Encoding/Decoding for Codable conformance
        enum CodingKeys: String, CodingKey {
            case id, date, items, notes, isEdited
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            date = try container.decode(Date.self, forKey: .date)
            let decodedItems = try container.decode([ChecklistItem].self, forKey: .items)
            itemCollection = ItemCollection(items: decodedItems)
            notes = try container.decode(String.self, forKey: .notes)
            isEdited = try container.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(date, forKey: .date)
            try container.encode(itemCollection.items, forKey: .items)
            try container.encode(notes, forKey: .notes)
            try container.encode(isEdited, forKey: .isEdited)
        }
        
        init(id: UUID = UUID(), date: Date = Date(), items: [ChecklistItem] = [], notes: String = "", isEdited: Bool = false) {
            self.id = id
            self.date = date
            self.itemCollection = ItemCollection(items: items)
            self.notes = notes
            self.isEdited = isEdited
        }
        
        mutating func toggleItem(_ item: ChecklistItem) {
            if let index = itemCollection.items.firstIndex(where: { $0.id == item.id }) {
                itemCollection.items[index].isCompleted.toggle()
            }
        }
        
        mutating func addItem(_ item: ChecklistItem) {
            itemCollection.items.append(item)
        }
        
        mutating func addItemAtBeginning(_ item: ChecklistItem) {
            itemCollection.items.insert(item, at: 0)
        }
        
        mutating func updateItem(_ item: ChecklistItem) {
            if let index = itemCollection.items.firstIndex(where: { $0.id == item.id }) {
                itemCollection.items[index] = item
            }
        }
        
        mutating func deleteItems(at indexSet: IndexSet) {
            itemCollection.items.remove(atOffsets: indexSet)
        }
        
        mutating func moveItems(from source: IndexSet, to destination: Int) {
            itemCollection.items.move(fromOffsets: source, toOffset: destination)
        }
        
        mutating func updateNotes(_ newNotes: String) {
            // Ensure notes don't exceed 2000 characters
            notes = String(newNotes.prefix(2000))
        }
        
        // Efficiently remove all items at once
        mutating func removeAllItems() {
            itemCollection.items = []
        }
        
        // Efficiently remove all items that belong to a specific group
        mutating func removeAllItemsInGroup(groupId: UUID) {
            itemCollection.items.removeAll(where: { $0.groupId == groupId })
        }
    }
} 
