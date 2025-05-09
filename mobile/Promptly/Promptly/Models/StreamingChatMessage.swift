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
    
    /// Reference to the final CoreData ChecklistOutline object (used only when outline is complete)
    @Published var checklistOutline: ChecklistOutline?
    
    /// Flag indicating if this message is building an outline progressively
    @Published var isBuildingOutline: Bool = false
    
    /// Properties for temporary outline data during streaming (without using CoreData)
    @Published var outlineSummary: String?
    @Published var outlinePeriod: String?
    @Published var outlineStartDate: Date?
    @Published var outlineEndDate: Date?
    @Published var outlineLineItems: [String] = []
    
    /// Initialize a new streaming chat message
    /// - Parameters:
    ///   - id: Optional UUID for the message (defaults to a new UUID)
    ///   - content: Initial content (empty for streaming assistant messages)
    ///   - role: "user" or "assistant"
    ///   - timestamp: Message timestamp (defaults to current time)
    ///   - isComplete: Whether the message is complete (true for user messages, false for streaming)
    ///   - isError: Whether this is an error message
    ///   - isReportMessage: Whether this is a report message
    ///   - checklistOutline: Optional final CoreData checklist outline
    ///   - isBuildingOutline: Whether this message is currently building an outline progressively
    init(
        id: UUID = UUID(),
        content: String,
        role: String,
        timestamp: Date = Date(),
        isComplete: Bool = false,
        isStreaming: Bool = false,
        isError: Bool = false,
        isReportMessage: Bool = false,
        checklistOutline: ChecklistOutline? = nil,
        isBuildingOutline: Bool = false
    ) {
        self.id = id
        self.content = content
        self.role = role
        self.timestamp = timestamp
        self.isComplete = isComplete
        self.isStreaming = isStreaming
        self.isError = isError
        self.isReportMessage = isReportMessage
        self.checklistOutline = checklistOutline
        self.isBuildingOutline = isBuildingOutline
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
    static func createUserMessage(content: String, id: UUID = UUID()) -> StreamingChatMessage {
        return StreamingChatMessage(
            id: id,
            content: content,
            role: "user",
            isComplete: true
        )
    }
    
    /// Create an assistant message that will be streaming
    static func createAssistantMessage(id: UUID = UUID()) -> StreamingChatMessage {
        return StreamingChatMessage(
            id: id,
            content: "",
            role: "assistant",
            isComplete: false,
            isStreaming: true
        )
    }
    
    /// Create an assistant message that is building an outline
    static func createOutlineBuildingMessage(id: UUID = UUID()) -> StreamingChatMessage {
        return StreamingChatMessage(
            id: id,
            content: "Creating an outline based on your request...",
            role: "assistant",
            isComplete: false,
            isStreaming: true,
            isBuildingOutline: true
        )
    }
    
    /// Create a complete assistant message (for non-streaming or already complete)
    static func createCompleteAssistantMessage(content: String, id: UUID = UUID()) -> StreamingChatMessage {
        return StreamingChatMessage(
            id: id,
            content: content,
            role: "assistant",
            isComplete: true
        )
    }
    
    /// Create an error message
    static func createErrorMessage(content: String, id: UUID = UUID()) -> StreamingChatMessage {
        return StreamingChatMessage(
            id: id,
            content: content,
            role: "assistant",
            isComplete: true,
            isError: true
        )
    }
    
    /// Create a report message
    static func createReportMessage(content: String, id: UUID = UUID()) -> StreamingChatMessage {
        return StreamingChatMessage(
            id: id,
            content: content,
            role: "assistant",
            isComplete: true,
            isReportMessage: true
        )
    }
    
    /// Create an assistant message with an outline
    static func createOutlineMessage(content: String, outline: ChecklistOutline, id: UUID = UUID()) -> StreamingChatMessage {
        return StreamingChatMessage(
            id: id,
            content: content,
            role: "assistant",
            isComplete: true,
            isReportMessage: false,
            checklistOutline: outline
        )
    }
} 
