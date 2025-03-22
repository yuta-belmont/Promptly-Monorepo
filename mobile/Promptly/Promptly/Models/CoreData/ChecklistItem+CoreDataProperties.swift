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
    @NSManaged public var subItems: NSOrderedSet?
}

// MARK: - SubItems Accessors

extension ChecklistItem {
    @objc(insertObject:inSubItemsAtIndex:)
    @NSManaged public func insertIntoSubItems(_ value: SubItem, at idx: Int)
    
    @objc(removeObjectFromSubItemsAtIndex:)
    @NSManaged public func removeFromSubItems(at idx: Int)
    
    @objc(insertSubItems:atIndexes:)
    @NSManaged public func insertIntoSubItems(_ values: [SubItem], at indexes: NSIndexSet)
    
    @objc(removeSubItemsAtIndexes:)
    @NSManaged public func removeFromSubItems(at indexes: NSIndexSet)
    
    @objc(replaceObjectInSubItemsAtIndex:withObject:)
    @NSManaged public func replaceSubItems(at idx: Int, with value: SubItem)
    
    @objc(replaceSubItemsAtIndexes:withSubItems:)
    @NSManaged public func replaceSubItems(at indexes: NSIndexSet, with values: [SubItem])
    
    @objc(addSubItemsObject:)
    @NSManaged public func addToSubItems(_ value: SubItem)
    
    @objc(removeSubItemsObject:)
    @NSManaged public func removeFromSubItems(_ value: SubItem)
    
    @objc(addSubItems:)
    @NSManaged public func addToSubItems(_ values: NSOrderedSet)
    
    @objc(removeSubItems:)
    @NSManaged public func removeFromSubItems(_ values: NSOrderedSet)
} 