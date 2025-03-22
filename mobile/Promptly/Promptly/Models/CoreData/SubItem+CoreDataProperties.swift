import Foundation
import CoreData

extension SubItem {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<SubItem> {
        return NSFetchRequest<SubItem>(entityName: "SubItem")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var isCompleted: Bool
    @NSManaged public var title: String?
    @NSManaged public var parent: ChecklistItem?
} 