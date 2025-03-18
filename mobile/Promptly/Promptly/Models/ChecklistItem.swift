//
//  ChecklistItem.swift
//  Promptly
//
//  Created by Yuta Belmont on 2/27/25.
//

import Foundation

extension Models {
    struct ChecklistItem: Identifiable, Codable, Equatable, Hashable {
        let id: UUID
        var title: String
        var notification: Date?
        var isCompleted: Bool
        private(set) var group: ItemGroup?  // Direct reference to the ItemGroup
        let date: Date  // The date this item belongs to
        
        // Computed property for backward compatibility
        var groupId: UUID? {
            return group?.id
        }
        
        init(id: UUID = UUID(), title: String, date: Date, isCompleted: Bool = false, notification: Date? = nil, group: ItemGroup? = nil) {
            self.id = id
            self.title = title
            self.date = date
            self.isCompleted = isCompleted
            self.notification = notification
            self.group = group
        }
        
        // For backward compatibility - initialize with groupId
        init(id: UUID = UUID(), title: String, date: Date, isCompleted: Bool = false, notification: Date? = nil, groupId: UUID? = nil) {
            self.id = id
            self.title = title
            self.date = date
            self.isCompleted = isCompleted
            self.notification = notification
            
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
        
        static func == (lhs: ChecklistItem, rhs: ChecklistItem) -> Bool {
            lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
}
    
