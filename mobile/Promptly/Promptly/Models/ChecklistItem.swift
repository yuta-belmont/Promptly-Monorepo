//
//  ChecklistItem.swift
//  Promptly
//
//  Created by Yuta Belmont on 2/27/25.
//

import Foundation

// Reference type collection to hold SubItems
class SubItemCollection {
    var items: [Models.SubItem]
    
    init(items: [Models.SubItem] = []) {
        self.items = items
    }
}

extension Models {
    struct ChecklistItem: Identifiable, Codable, Equatable, Hashable {
        let id: UUID
        var title: String
        var notification: Date?
        var isCompleted: Bool
        private(set) var group: ItemGroup?  // Direct reference to the ItemGroup
        let date: Date  // The date this item belongs to
        var subItemCollection: SubItemCollection
        
        // Computed property for backward compatibility
        var groupId: UUID? {
            return group?.id
        }
        
        // Computed property to maintain backward compatibility
        var subItems: [SubItem] {
            get { return subItemCollection.items }
            set { subItemCollection.items = newValue }
        }
        
        // Encoding/Decoding for Codable conformance
        enum CodingKeys: String, CodingKey {
            case id, title, notification, isCompleted, group, date, subItems
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            notification = try container.decodeIfPresent(Date.self, forKey: .notification)
            isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
            group = try container.decodeIfPresent(ItemGroup.self, forKey: .group)
            date = try container.decode(Date.self, forKey: .date)
            let decodedSubItems = try container.decode([SubItem].self, forKey: .subItems)
            subItemCollection = SubItemCollection(items: decodedSubItems)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(title, forKey: .title)
            try container.encodeIfPresent(notification, forKey: .notification)
            try container.encode(isCompleted, forKey: .isCompleted)
            try container.encodeIfPresent(group, forKey: .group)
            try container.encode(date, forKey: .date)
            try container.encode(subItemCollection.items, forKey: .subItems)
        }
        
        init(id: UUID = UUID(), title: String, date: Date, isCompleted: Bool = false, notification: Date? = nil, group: ItemGroup? = nil, subItems: [SubItem] = []) {
            self.id = id
            self.title = title
            self.date = date
            self.isCompleted = isCompleted
            self.notification = notification
            self.group = group
            self.subItemCollection = SubItemCollection(items: subItems)
        }
        
        // For backward compatibility - initialize with groupId
        init(id: UUID = UUID(), title: String, date: Date, isCompleted: Bool = false, notification: Date? = nil, groupId: UUID? = nil, subItems: [SubItem] = []) {
            self.id = id
            self.title = title
            self.date = date
            self.isCompleted = isCompleted
            self.notification = notification
            self.subItemCollection = SubItemCollection(items: subItems)
            
            // If groupId is provided, we'll need to set the group later
            // This is handled by the updateGroupId method
            self.group = nil
            
            // Note: The actual group object will need to be set after initialization
            // using the updateGroup method, since we can't access GroupStore here
        }
        
        // Update the group reference
        mutating func updateGroup(_ newGroup: ItemGroup?) {
            self.group = newGroup
        }
        
        // For backward compatibility - update using groupId
        mutating func updateGroupId(_ newGroupId: UUID?) {
            // This method now just clears the group if nil is provided
            // The actual group object will need to be set after this call
            // using the updateGroup method
            if newGroupId == nil {
                self.group = nil
            }
            // If newGroupId is not nil, the caller needs to use updateGroup with the actual ItemGroup
        }
        
        // Add a subItem
        mutating func addSubItem(_ subItem: SubItem) {
            subItemCollection.items.append(subItem)
        }
        
        // Remove a subItem by ID
        mutating func removeSubItem(withId id: UUID) {
            subItemCollection.items.removeAll { $0.id == id }
        }
        
        // Toggle a subItem's completion status
        mutating func toggleSubItem(withId id: UUID) {
            if let index = subItemCollection.items.firstIndex(where: { $0.id == id }) {
                subItemCollection.items[index].isCompleted.toggle()
            }
        }
        
        // Update a subItem's title
        mutating func updateSubItem(withId id: UUID, newTitle: String) {
            if let index = subItemCollection.items.firstIndex(where: { $0.id == id }) {
                subItemCollection.items[index].title = newTitle
            }
        }
        
        static func == (lhs: ChecklistItem, rhs: ChecklistItem) -> Bool {
            lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
}
    
