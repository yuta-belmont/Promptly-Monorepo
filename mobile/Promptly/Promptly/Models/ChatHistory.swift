import Foundation
import CoreData

@objc(ChatHistory)
public class ChatHistory: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var isMainHistory: Bool
    @NSManaged public var chatMessages: NSOrderedSet?
    
    // Direct accessor for messages as an array
    var messages: [ChatMessage] {
        get {
            let messagesArray = chatMessages?.array as? [ChatMessage] ?? []
            return messagesArray.sorted { $0.timestamp < $1.timestamp }
        }
    }
}

// MARK: - Convenience Methods
extension ChatHistory {
    @discardableResult
    static func create(in context: NSManagedObjectContext,
                      id: UUID = UUID(),
                      isMainHistory: Bool = false,
                      messages: [ChatMessage] = []) -> ChatHistory {
        // Use insertNewObject instead of direct initialization for better reliability
        let history = NSEntityDescription.insertNewObject(forEntityName: "ChatHistory", into: context) as! ChatHistory
        history.id = id
        history.isMainHistory = isMainHistory
        if !messages.isEmpty {
            history.chatMessages = NSOrderedSet(array: messages)
        }
        return history
    }
    
    func addMessage(_ message: ChatMessage) {
        // Create a mutable copy of the current ordered set
        let mutableMessages = NSMutableOrderedSet(orderedSet: chatMessages ?? NSOrderedSet())
        
        // Add the new message
        mutableMessages.add(message)
        
        // Update the chatMessages property
        chatMessages = mutableMessages
        
        // Set the inverse relationship
        message.chatHistory = self
    }
}

// MARK: - NSFetchRequest Extension
extension ChatHistory {
    static func fetchRequest() -> NSFetchRequest<ChatHistory> {
        return NSFetchRequest<ChatHistory>(entityName: "ChatHistory")
    }
}

// MARK: - Generated accessors for chatMessages
extension ChatHistory {
    @objc(insertObject:inChatMessagesAtIndex:)
    @NSManaged public func insertIntoChatMessages(_ value: ChatMessage, at idx: Int)
    
    @objc(removeObjectFromChatMessagesAtIndex:)
    @NSManaged public func removeFromChatMessages(at idx: Int)
    
    @objc(insertChatMessages:atIndexes:)
    @NSManaged public func insertIntoChatMessages(_ values: [ChatMessage], at indexes: NSIndexSet)
    
    @objc(removeChatMessagesAtIndexes:)
    @NSManaged public func removeFromChatMessages(at indexes: NSIndexSet)
    
    @objc(replaceObjectInChatMessagesAtIndex:withObject:)
    @NSManaged public func replaceChatMessages(at idx: Int, with value: ChatMessage)
    
    @objc(replaceChatMessagesAtIndexes:withChatMessages:)
    @NSManaged public func replaceChatMessages(at indexes: NSIndexSet, with values: [ChatMessage])
    
    @objc(addChatMessagesObject:)
    @NSManaged public func addToChatMessages(_ value: ChatMessage)
    
    @objc(removeChatMessagesObject:)
    @NSManaged public func removeFromChatMessages(_ value: ChatMessage)
    
    @objc(addChatMessages:)
    @NSManaged public func addToChatMessages(_ values: NSOrderedSet)
    
    @objc(removeChatMessages:)
    @NSManaged public func removeFromChatMessages(_ values: NSOrderedSet)
} 
