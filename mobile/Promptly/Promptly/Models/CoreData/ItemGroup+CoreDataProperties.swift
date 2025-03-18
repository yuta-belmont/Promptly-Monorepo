import Foundation
import CoreData

extension ItemGroup {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ItemGroup> {
        return NSFetchRequest<ItemGroup>(entityName: "ItemGroup")
    }

    @NSManaged public var colorBlue: Double
    @NSManaged public var colorGreen: Double
    @NSManaged public var colorRed: Double
    @NSManaged public var hasColor: Bool
    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var checklistItem: NSSet?
}

// MARK: Generated accessors for checklistItem
extension ItemGroup {
    @objc(addChecklistItemObject:)
    @NSManaged public func addToChecklistItem(_ value: ChecklistItem)

    @objc(removeChecklistItemObject:)
    @NSManaged public func removeFromChecklistItem(_ value: ChecklistItem)

    @objc(addChecklistItem:)
    @NSManaged public func addToChecklistItem(_ values: NSSet)

    @objc(removeChecklistItem:)
    @NSManaged public func removeFromChecklistItem(_ values: NSSet)
} 