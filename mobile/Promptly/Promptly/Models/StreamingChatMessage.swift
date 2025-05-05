import Foundation
import SwiftUI

/// A model for streaming chat messages that supports incremental updates
class StreamingChatMessage: Identifiable, ObservableObject {
    let id: UUID
    @Published var content: String
    let role: String // "user" or "assistant"
    let timestamp: Date
    @Published var isComplete: Bool
    @Published var isStreaming: Bool
    
    /// Flag indicating whether this message is a error message
    let isError: Bool
    
    /// Flag indicating if the message is a report
    let isReportMessage: Bool
    
    /// Reference to an outline if available
    var outline: ChecklistOutline?
    
    /// Initialize a new streaming chat message
    /// - Parameters:
    ///   - id: Optional UUID for the message (defaults to a new UUID)
    ///   - content: Initial content (empty for streaming assistant messages)
    ///   - role: "user" or "assistant"
    ///   - timestamp: Message timestamp (defaults to current time)
    ///   - isComplete: Whether the message is complete (true for user messages, false for streaming)
    ///   - isError: Whether this is an error message
    ///   - isReportMessage: Whether this is a report message
    ///   - outline: Optional checklist outline
    init(
        id: UUID = UUID(),
        content: String,
        role: String,
        timestamp: Date = Date(),
        isComplete: Bool = false,
        isStreaming: Bool = false,
        isError: Bool = false,
        isReportMessage: Bool = false,
        outline: ChecklistOutline? = nil
    ) {
        self.id = id
        self.content = content
        self.role = role
        self.timestamp = timestamp
        self.isComplete = isComplete
        self.isStreaming = isStreaming
        self.isError = isError
        self.isReportMessage = isReportMessage
        self.outline = outline
    }
    
    /// Append text to the content of the message
    /// - Parameter text: The text to append
    @MainActor
    func appendContent(_ text: String) {
        content.append(text)
    }
    
    /// Replace the entire content of the message
    /// - Parameter text: The new text
    @MainActor
    func replaceContent(with text: String) {
        content = text
    }
    
    /// Mark the message as complete
    @MainActor
    func markAsComplete() {
        isComplete = true
        isStreaming = false
    }
    
    /// Start streaming for this message
    @MainActor
    func startStreaming() {
        isStreaming = true
        isComplete = false
    }
    
    /// Stop streaming for this message
    @MainActor
    func stopStreaming() {
        isStreaming = false
    }
}

/// Factory for creating different types of streaming chat messages
struct StreamingChatMessageFactory {
    /// Create a user message (always complete on creation)
    static func createUserMessage(content: String) -> StreamingChatMessage {
        return StreamingChatMessage(
            content: content,
            role: "user",
            isComplete: true
        )
    }
    
    /// Create an assistant message that will be streaming
    static func createAssistantMessage() -> StreamingChatMessage {
        return StreamingChatMessage(
            content: "",
            role: "assistant",
            isComplete: false,
            isStreaming: true
        )
    }
    
    /// Create a complete assistant message (for non-streaming or already complete)
    static func createCompleteAssistantMessage(content: String) -> StreamingChatMessage {
        return StreamingChatMessage(
            content: content,
            role: "assistant",
            isComplete: true
        )
    }
    
    /// Create an error message
    static func createErrorMessage(content: String) -> StreamingChatMessage {
        return StreamingChatMessage(
            content: content,
            role: "assistant",
            isComplete: true,
            isError: true
        )
    }
    
    /// Create a report message
    static func createReportMessage(content: String) -> StreamingChatMessage {
        return StreamingChatMessage(
            content: content,
            role: "assistant",
            isComplete: true,
            isReportMessage: true
        )
    }
    
    /// Create an assistant message with an outline
    static func createOutlineMessage(content: String, outline: ChecklistOutline) -> StreamingChatMessage {
        return StreamingChatMessage(
            content: content,
            role: "assistant",
            isComplete: true,
            isReportMessage: false,
            outline: outline
        )
    }
} 