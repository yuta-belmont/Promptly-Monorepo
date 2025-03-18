import Foundation
import CoreData

@objc(ChecklistItem)
public class ChecklistItem: NSManagedObject {
    // Custom methods can be added here
    
    // Helper method to convert to the struct representation
    func toStruct() -> Models.ChecklistItem {
        // Safely handle the itemGroup relationship
        var groupStruct: Models.ItemGroup? = nil
        
        // Only try to convert the group if it exists
        if let group = itemGroup {
            // Avoid potential circular references by not accessing the checklistItem relationship
            // when converting from ItemGroup to struct
            groupStruct = Models.ItemGroup(
                id: group.id ?? UUID(),
                title: group.title ?? "",
                items: [:], // Empty dictionary to avoid circular references
                colorRed: group.colorRed,
                colorGreen: group.colorGreen,
                colorBlue: group.colorBlue,
                hasColor: group.hasColor
            )
        }
        
        return Models.ChecklistItem(
            id: id ?? UUID(),
            title: title ?? "",
            date: date ?? Date(),
            isCompleted: isCompleted,
            notification: notification,
            group: groupStruct
        )
    }
    
    // Helper method to update from a struct
    func update(from structModel: Models.ChecklistItem, context: NSManagedObjectContext) {
        self.id = structModel.id
        self.title = structModel.title
        self.date = structModel.date
        self.isCompleted = structModel.isCompleted
        self.notification = structModel.notification
        
        // We don't update relationships here as they're handled separately
    }
    
    // Helper method to create a new ChecklistItem from a struct
    static func create(from structModel: Models.ChecklistItem, context: NSManagedObjectContext) -> ChecklistItem {
        // Use insertNewObject instead of direct initialization for better reliability
        let item = NSEntityDescription.insertNewObject(forEntityName: "ChecklistItem", into: context) as! ChecklistItem
        item.id = structModel.id
        item.title = structModel.title
        item.date = structModel.date
        item.isCompleted = structModel.isCompleted
        item.notification = structModel.notification
        return item
    }
} 
