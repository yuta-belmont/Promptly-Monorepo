//
//  ChatMessage.swift
//  Promptly
//
//  Created by Yuta Belmont on 2/27/25.
//

import Foundation
import CoreData

// Define string constants for roles instead of enum
struct MessageRoles {
    static let user = "user"
    static let assistant = "assistant"
    // You could also add "system" if you'd like system prompts
}

@objc(ChatMessage)
public class ChatMessage: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var content: String
    @NSManaged public var role: String // Direct string property instead of computed property
    @NSManaged public var timestamp: Date
    @NSManaged public var isReportMessage: Bool

    @NSManaged public var chatHistory: ChatHistory?
}

// MARK: - Convenience Methods
extension ChatMessage {
    // Factory method to create a new ChatMessage
    @discardableResult
    static func create(in context: NSManagedObjectContext,
                      id: UUID = UUID(),
                      role: String, // Changed parameter type to String
                      content: String,
                      timestamp: Date = Date(),
                      isReportMessage: Bool = false,
                      chatHistory: ChatHistory? = nil) -> ChatMessage {
        // Use insertNewObject instead of direct initialization for better reliability
        let message = NSEntityDescription.insertNewObject(forEntityName: "ChatMessage", into: context) as! ChatMessage
        message.id = id
        message.role = role // Direct assignment
        message.content = content
        message.timestamp = timestamp
        message.isReportMessage = isReportMessage
        message.chatHistory = chatHistory
        return message
    }
}

// MARK: - NSFetchRequest Extension
extension ChatMessage {
    static func fetchRequest() -> NSFetchRequest<ChatMessage> {
        return NSFetchRequest<ChatMessage>(entityName: "ChatMessage")
    }
}
