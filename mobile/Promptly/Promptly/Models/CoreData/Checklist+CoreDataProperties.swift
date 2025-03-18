import Foundation
import CoreData

extension Checklist {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Checklist> {
        return NSFetchRequest<Checklist>(entityName: "Checklist")
    }

    @NSManaged public var date: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var notes: String?
    @NSManaged public var checklistItem: NSSet?
}

// MARK: Generated accessors for checklistItem
extension Checklist {
    @objc(addChecklistItemObject:)
    @NSManaged public func addToChecklistItem(_ value: ChecklistItem)

    @objc(removeChecklistItemObject:)
    @NSManaged public func removeFromChecklistItem(_ value: ChecklistItem)

    @objc(addChecklistItem:)
    @NSManaged public func addToChecklistItem(_ values: NSSet)

    @objc(removeChecklistItem:)
    @NSManaged public func removeFromChecklistItem(_ values: NSSet)
} 