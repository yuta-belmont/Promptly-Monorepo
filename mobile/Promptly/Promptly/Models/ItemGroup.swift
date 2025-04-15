import Foundation
import SwiftUI

extension Models {
    struct ItemGroup: Identifiable, Codable, Equatable {
        let id: UUID
        private(set) var title: String
        private(set) var items: [UUID: ChecklistItem]  // Store direct references to ChecklistItem objects
        private(set) var notes: String
        
        // Color properties
        private(set) var colorRed: Double
        private(set) var colorGreen: Double
        private(set) var colorBlue: Double
        private(set) var hasColor: Bool
        
        init(id: UUID = UUID(), title: String, items: [UUID: ChecklistItem] = [:], colorRed: Double = 0, colorGreen: Double = 0, colorBlue: Double = 0, hasColor: Bool = false, notes: String = "") {
            self.id = id
            self.title = String(title.prefix(200))  // Safety limit of 200 characters
            self.items = items
            self.colorRed = max(0, min(1, colorRed))       // Clamp between 0 and 1
            self.colorGreen = max(0, min(1, colorGreen))   // Clamp between 0 and 1
            self.colorBlue = max(0, min(1, colorBlue))     // Clamp between 0 and 1
            self.hasColor = hasColor
            self.notes = notes
        }
        
        // MARK: - Color Methods
        
        /// Get the color as a SwiftUI Color
        func getColor() -> Color? {
            guard hasColor else { return nil }
            return Color(red: colorRed, green: colorGreen, blue: colorBlue)
        }
        
        /// Set all color components at once
        mutating func setColor(red: Double, green: Double, blue: Double) {
            colorRed = max(0, min(1, red))
            colorGreen = max(0, min(1, green))
            colorBlue = max(0, min(1, blue))
            hasColor = true
        }
        
        /// Set color from a SwiftUI Color
        mutating func setColor(_ color: Color?) {
            if let color = color {
                // Convert SwiftUI Color to RGB components
                let uiColor = UIColor(color)
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                
                uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                setColor(red: Double(red), green: Double(green), blue: Double(blue))
            } else {
                clearColor()
            }
        }
        
        /// Clear the color
        mutating func clearColor() {
            colorRed = 0
            colorGreen = 0
            colorBlue = 0
            hasColor = false
        }
        
        // MARK: - Mutating Methods
        
        mutating func addItem(_ item: ChecklistItem) {
            items[item.id] = item
        }
        
        mutating func removeItem(_ itemId: UUID) {
            items.removeValue(forKey: itemId)
        }
        
        mutating func updateTitle(_ newTitle: String) {
            title = String(newTitle.prefix(200))  // Safety limit of 200 characters
        }
        
        mutating func updateNotes(_ newNotes: String) {
            notes = newNotes
        }
        
        // MARK: - Query Methods
        
        func containsItem(_ itemId: UUID) -> Bool {
            return items.keys.contains(itemId)
        }
        
        var itemIds: Set<UUID> {
            Set(items.keys)
        }
        
        func getAllItems() -> [ChecklistItem] {
            // Return items sorted by date
            let allItems = items.values.sorted { $0.date < $1.date }
            return allItems
        }
        
        // For backward compatibility
        func getAllItemIds() -> [UUID] {
            return items.keys.sorted { 
                guard let item1 = items[$0], let item2 = items[$1] else { return false }
                return item1.date < item2.date
            }
        }
        
        // MARK: - Equatable
        
        static func == (lhs: ItemGroup, rhs: ItemGroup) -> Bool {
            lhs.id == rhs.id
        }
    }
}

// MARK: - Core Data Preparation
extension Models.ItemGroup {
    // These methods will make migration to Core Data easier in the future
    
    /// Get individual color components
    func getColorComponents() -> (red: Double, green: Double, blue: Double, hasColor: Bool) {
        guard hasColor else {
            return (0, 0, 0, false)
        }
        return (colorRed, colorGreen, colorBlue, true)
    }
    
    /// Create an ItemGroup from individual color components
    static func fromColorComponents(id: UUID, title: String, items: [UUID: Models.ChecklistItem], 
                                   red: Double, green: Double, blue: Double, hasColor: Bool, notes: String = "") -> Models.ItemGroup {
        return Models.ItemGroup(id: id, title: title, items: items, 
                         colorRed: red, colorGreen: green, colorBlue: blue, hasColor: hasColor, notes: notes)
    }
    
    /// Convert to SwiftUI Color
    func toSwiftUIColor() -> Color? {
        guard hasColor else { return nil }
        return Color(red: colorRed, green: colorGreen, blue: colorBlue)
    }
    
    // For backward compatibility - convert from old format
    static func fromLegacyFormat(id: UUID, title: String, itemDates: [UUID: Date],
                                red: Double, green: Double, blue: Double, hasColor: Bool) -> Models.ItemGroup {
        // Create an empty group with the same properties
        return Models.ItemGroup(id: id, title: title, items: [:],
                         colorRed: red, colorGreen: green, colorBlue: blue, hasColor: hasColor)
    }
} 
