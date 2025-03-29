import Foundation
import CoreData

@objc(Checklist)
public class Checklist: NSManagedObject {
    // Custom methods can be added here
    
    // Helper method to convert to the struct representation
    func toStruct() -> Models.Checklist {
        var items: [Models.ChecklistItem] = []
        
        // Access the ordered relationship using mutableOrderedSetValue which is more reliable
        let orderedItems = self.mutableOrderedSetValue(forKey: "checklistItem")
        
        // Process each item in the correct order
        for i in 0..<orderedItems.count {
            if let item = orderedItems[i] as? ChecklistItem {
                let itemStruct = item.toStruct()
                items.append(itemStruct)
            }
        }
        
        // Create a Checklist with the ItemCollection
        return Models.Checklist(
            id: id ?? UUID(),
            date: date ?? Date(),
            items: items, // The initializer will create the ItemCollection for us
            notes: notes ?? ""
        )
    }
    
    // Helper method to update from a struct
    func update(from structModel: Models.Checklist, context: NSManagedObjectContext) {
        self.id = structModel.id
        self.date = structModel.date
        self.notes = structModel.notes
        
        // We don't update relationships here as they're handled separately
    }
    
    // Helper method to create a new Checklist from a struct
    static func create(from structModel: Models.Checklist, context: NSManagedObjectContext) -> Checklist {
        // Use insertNewObject instead of direct initialization for better reliability
        let checklist = NSEntityDescription.insertNewObject(forEntityName: "Checklist", into: context) as! Checklist
        checklist.id = structModel.id
        checklist.date = structModel.date
        checklist.notes = structModel.notes
        return checklist
    }
} 
