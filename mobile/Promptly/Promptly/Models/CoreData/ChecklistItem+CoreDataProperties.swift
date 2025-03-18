import Foundation
import CoreData

extension ChecklistItem {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChecklistItem> {
        return NSFetchRequest<ChecklistItem>(entityName: "ChecklistItem")
    }

    @NSManaged public var date: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var isCompleted: Bool
    @NSManaged public var notification: Date?
    @NSManaged public var title: String?
    @NSManaged public var checklist: Checklist?
    @NSManaged public var itemGroup: ItemGroup?
} 