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
        
        // Convert subItems to array of struct models
        var subItemStructs: [Models.SubItem] = []
        if let subItemsSet = subItems {
            for case let subItem as SubItem in subItemsSet {
                let subItemStruct = Models.SubItem(
                    id: subItem.id ?? UUID(),
                    title: subItem.title ?? "",
                    isCompleted: subItem.isCompleted
                )
                subItemStructs.append(subItemStruct)
            }
        }
        
        return Models.ChecklistItem(
            id: id ?? UUID(),
            title: title ?? "",
            date: date ?? Date(),
            isCompleted: isCompleted,
            notification: notification,
            group: groupStruct,
            subItems: subItemStructs
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
    
    // Helper method to sync subItems from struct model
    func syncSubItems(from structModel: Models.ChecklistItem, context: NSManagedObjectContext) {
        // Remove all existing subItems first
        if let subItemsSet = subItems as? NSOrderedSet, subItemsSet.count > 0 {
            removeFromSubItems(subItemsSet)
        }
        
        // Create new subItems from the struct model
        for subItemStruct in structModel.subItems {
            // Create a new SubItem entity
            let subItem = NSEntityDescription.insertNewObject(forEntityName: "SubItem", into: context) as! SubItem
            subItem.id = subItemStruct.id
            subItem.title = subItemStruct.title
            subItem.isCompleted = subItemStruct.isCompleted
            subItem.parent = self
            
            // Add to the subItems relationship
            addToSubItems(subItem)
        }
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
        
        // Create and add subItems
        item.syncSubItems(from: structModel, context: context)
        
        return item
    }
} 
