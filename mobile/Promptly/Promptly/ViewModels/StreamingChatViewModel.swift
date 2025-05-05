import SwiftUI
import Combine

@MainActor
final class StreamingChatViewModel: ObservableObject {
    // Static shared instance
    static let shared = StreamingChatViewModel()
    
    // Published properties for UI binding
    @Published var messages: [StreamingChatMessage] = []
    @Published var userInput: String = ""
    @Published var isLoading: Bool = false
    @Published var isStreaming: Bool = false
    @Published var unreadCount: Int = 0
    @Published var isExpanded: Bool = false
    
    // Services
    private let pubSubChatService = PubSubChatService.shared
    private let authManager = AuthManager.shared
    
    // Current streaming message
    private var currentStreamingMessage: StreamingChatMessage?
    
    // Private initializer for singleton pattern
    private init() {
        setupCallbacks()
    }
    
    // Set up the callbacks for pubsub service streaming events
    private func setupCallbacks() {
        // Handle chunk received during streaming
        pubSubChatService.onChunkReceived = { [weak self] chunk in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleChunkReceived(chunk)
            }
        }
        
        // Handle message completed event
        pubSubChatService.onMessageCompleted = { [weak self] fullText in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleMessageCompleted(fullText)
            }
        }
        
        // Handle error events
        pubSubChatService.onError = { [weak self] error in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleError(error)
            }
        }
    }
    
    // MARK: - Message Handling
    
    // Send a message
    func sendMessage(_ text: String) {
        // Check if user is authenticated
        guard authManager.isAuthenticated && !authManager.isGuestUser else {
            return
        }
        
        // Trim whitespace
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        // Clear the input immediately
        userInput = ""
        
        // Create and add user message
        let userMessage = StreamingChatMessageFactory.createUserMessage(content: trimmedText)
        messages.append(userMessage)
        
        // Create and add a streaming assistant message
        let assistantMessage = StreamingChatMessageFactory.createAssistantMessage()
        messages.append(assistantMessage)
        currentStreamingMessage = assistantMessage
        
        // Update UI state
        isLoading = true
        isStreaming = true
        
        // Prepare message history context
        let context = prepareMessageContext()
        
        // Send the message to the PubSub service
        Task {
            do {
                _ = try await pubSubChatService.sendMessage(
                    content: trimmedText,
                    messageHistory: context
                )
                // Request ID is returned but we don't need to store it
                // The SSE connection is managed by PubSubChatService
            } catch {
                // Handle send error
                handleError(error)
            }
        }
    }
    
    // Handle received chunk during streaming
    private func handleChunkReceived(_ chunk: String) {
        if let currentMessage = currentStreamingMessage {
            // Append the chunk to the current message
            currentMessage.appendContent(chunk)
        } else {
            // If we don't have a streaming message, create one
            let newMessage = StreamingChatMessageFactory.createAssistantMessage()
            newMessage.appendContent(chunk)
            messages.append(newMessage)
            currentStreamingMessage = newMessage
            isStreaming = true
        }
    }
    
    // Handle message completion
    private func handleMessageCompleted(_ fullText: String) {
        if let currentMessage = currentStreamingMessage {
            // Mark current message as complete
            currentMessage.markAsComplete()
            
            // Check for outline data
            if let data = fullText.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let outline = json["outline"] as? [String: Any],
               let response = json["response"] as? String {
                
                // Create a ChecklistOutline entity
                let outlineModel = createOutlineModel(from: outline)
                
                // Update the message with outline and response
                if let outlineModel = outlineModel {
                    currentMessage.outline = outlineModel
                }
                currentMessage.replaceContent(with: response)
            }
        } else if !fullText.isEmpty {
            // Create a new complete message if we don't have one
            let newMessage = StreamingChatMessageFactory.createCompleteAssistantMessage(content: fullText)
            messages.append(newMessage)
        }
        
        // Reset state
        isLoading = false
        isStreaming = false
        currentStreamingMessage = nil
        
        // Increment unread count if not expanded
        if !isExpanded {
            unreadCount += 1
        }
    }
    
    // Handle error
    private func handleError(_ error: Error) {
        // Create an error message
        let errorMessage: String
        if let pubSubError = error as? PubSubChatError {
            switch pubSubError {
            case .notAuthenticated:
                errorMessage = "You are not authenticated. Please log in again."
            case .invalidResponse(let details):
                errorMessage = "Invalid response: \(details)"
            case .networkError(let details):
                errorMessage = "Network error: \(details)"
            case .sseError(let details):
                errorMessage = "Streaming error: \(details)"
            }
        } else {
            errorMessage = "Error: \(error.localizedDescription)"
        }
        
        // If we have a streaming message, mark it as complete and update content
        if let currentMessage = currentStreamingMessage {
            currentMessage.markAsComplete()
            currentMessage.replaceContent(with: errorMessage)
        } else {
            // Create a new error message
            let newErrorMessage = StreamingChatMessageFactory.createErrorMessage(content: errorMessage)
            messages.append(newErrorMessage)
        }
        
        // Reset state
        isLoading = false
        isStreaming = false
        currentStreamingMessage = nil
    }
    
    // MARK: - Helper Methods
    
    // Prepare message context for API
    private func prepareMessageContext() -> [[String: Any]] {
        // Only include the most recent messages (up to 10)
        let recentMessages = messages.suffix(10)
        
        // Convert to dictionaries for the API
        return recentMessages.map { message in
            return [
                "role": message.role,
                "content": message.content
            ]
        }
    }
    
    // Create an outline model from JSON data
    private func createOutlineModel(from outlineData: [String: Any]) -> ChecklistOutline? {
        // Create a new ChecklistOutline entity
        let outline = ChecklistOutline()
        outline.id = UUID()
        outline.timestamp = Date()
        
        // Extract data from the outline JSON
        if let summary = outlineData["summary"] as? String {
            outline.summary = summary
        }
        
        if let period = outlineData["period"] as? String {
            outline.period = period
        }
        
        // Extract dates using DateFormatter
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        if let startDateStr = outlineData["start_date"] as? String,
           let startDate = dateFormatter.date(from: startDateStr) {
            outline.startDate = startDate
        }
        
        if let endDateStr = outlineData["end_date"] as? String,
           let endDate = dateFormatter.date(from: endDateStr) {
            outline.endDate = endDate
        }
        
        // Extract line items
        if let details = outlineData["details"] as? [[String: Any]] {
            var lineItems: [String] = []
            for detail in details {
                if let title = detail["title"] as? String,
                   let breakdown = detail["breakdown"] as? String {
                    lineItems.append("\(title): \(breakdown)")
                }
            }
            outline.lineItem = lineItems as NSArray
        }
        
        return outline
    }
    
    // MARK: - UI State Management
    
    // Clear unread count
    func clearUnreadCount() {
        unreadCount = 0
    }
    
    // Clean up resources
    func cleanup() {
        pubSubChatService.cleanup()
    }
    
    // Accept outline
    func acceptOutline() {
        if let message = messages.first(where: { $0.outline?.isDone == false }),
           let outline = message.outline {
            
            // Mark outline as done
            outline.isDone = true
            
            // Prepare outline data for API
            var outlineData: [String: Any] = [:]
            
            if let summary = outline.summary {
                outlineData["summary"] = summary
            }
            
            if let period = outline.period {
                outlineData["period"] = period
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            if let startDate = outline.startDate {
                outlineData["start_date"] = dateFormatter.string(from: startDate)
            }
            
            if let endDate = outline.endDate {
                outlineData["end_date"] = dateFormatter.string(from: endDate)
            }
            
            if let lineItems = outline.lineItem as? [String] {
                outlineData["line_item"] = lineItems
            }
            
            // Send outline to server
            Task {
                do {
                    _ = try await pubSubChatService.sendChecklistRequest(
                        content: "",
                        outline: outlineData
                    )
                    
                    // Create a new streaming assistant message for the response
                    let assistantMessage = StreamingChatMessageFactory.createAssistantMessage()
                    messages.append(assistantMessage)
                    currentStreamingMessage = assistantMessage
                    
                    // Update UI state
                    isLoading = true
                    isStreaming = true
                    
                } catch {
                    handleError(error)
                }
            }
        }
    }
    
    // Decline outline
    func declineOutline() {
        if let message = messages.first(where: { $0.outline?.isDone == false }),
           let outline = message.outline {
            outline.isDone = true
        }
    }
    
    // Check if there's a pending outline
    var hasPendingOutline: Bool {
        return messages.contains { $0.outline?.isDone == false }
    }
} 