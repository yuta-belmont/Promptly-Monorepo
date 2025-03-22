import Foundation
import CoreData

@objc(SubItem)
public class SubItem: NSManagedObject {
    // Custom methods can be added here
    
    // Helper method to convert to a struct representation
    func toStruct() -> Models.SubItem {
        return Models.SubItem(
            id: id ?? UUID(),
            title: title ?? "",
            isCompleted: isCompleted
        )
    }
    
    // Helper method to update from a struct
    func update(from structModel: Models.SubItem) {
        self.id = structModel.id
        self.title = structModel.title
        self.isCompleted = structModel.isCompleted
        // parent relationship is managed separately
    }
    
    // Helper method to create a new SubItem from a struct
    static func create(from structModel: Models.SubItem, context: NSManagedObjectContext) -> SubItem {
        let subItem = NSEntityDescription.insertNewObject(forEntityName: "SubItem", into: context) as! SubItem
        subItem.id = structModel.id
        subItem.title = structModel.title
        subItem.isCompleted = structModel.isCompleted
        return subItem
    }
} 