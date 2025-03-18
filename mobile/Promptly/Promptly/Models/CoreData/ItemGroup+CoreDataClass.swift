import Foundation
import CoreData
import SwiftUI

@objc(ItemGroup)
public class ItemGroup: NSManagedObject {
    // Custom methods can be added here
    
    // Helper method to convert to the struct representation
    func toStruct() -> Models.ItemGroup {
        // Safely access the checklistItem relationship
        var itemsDictionary: [UUID: Models.ChecklistItem] = [:]
        
        // Use a safer approach to access the relationship
        if let checklistItemSet = checklistItem {
            // Convert NSSet to Array safely
            let itemsArray = checklistItemSet.allObjects as? [ChecklistItem] ?? []
            
            // Process each item safely
            for item in itemsArray {
                if let id = item.id {
                    // Safely convert each item to its struct representation
                    do {
                        let itemStruct = item.toStruct()
                        itemsDictionary[id] = itemStruct
                    } catch {
                        print("Error converting item to struct: \(error)")
                    }
                }
            }
        }
        
        return Models.ItemGroup(
            id: id ?? UUID(),
            title: title ?? "",
            items: itemsDictionary,
            colorRed: colorRed,
            colorGreen: colorGreen,
            colorBlue: colorBlue,
            hasColor: hasColor
        )
    }
    
    // Helper method to update from a struct
    func update(from structModel: Models.ItemGroup, context: NSManagedObjectContext) {
        self.id = structModel.id
        self.title = structModel.title
        self.colorRed = structModel.colorRed
        self.colorGreen = structModel.colorGreen
        self.colorBlue = structModel.colorBlue
        self.hasColor = structModel.hasColor
        
        // We don't update relationships here as they're handled separately
    }
    
    // Helper method to create a new ItemGroup from a struct
    static func create(from structModel: Models.ItemGroup, context: NSManagedObjectContext) -> ItemGroup {
        // Use insertNewObject instead of direct initialization for better reliability
        let group = NSEntityDescription.insertNewObject(forEntityName: "ItemGroup", into: context) as! ItemGroup
        group.id = structModel.id
        group.title = structModel.title
        group.colorRed = structModel.colorRed
        group.colorGreen = structModel.colorGreen
        group.colorBlue = structModel.colorBlue
        group.hasColor = structModel.hasColor
        return group
    }
    
    // Helper method to get color as SwiftUI Color
    func getColor() -> Color? {
        guard hasColor else { return nil }
        return Color(red: colorRed, green: colorGreen, blue: colorBlue)
    }
} 