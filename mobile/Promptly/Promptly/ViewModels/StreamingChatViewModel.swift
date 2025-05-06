import SwiftUI
import Combine
import CoreData

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
    
    // Add these new properties after the existing properties
    private var activeOutlines: [String: ChecklistOutline] = [:]
    private var currentOutlineRequestId: String?
    
    // Completion handler for outline generation
    var outlineCompletionHandler: ((Error?) -> Void)?
    
    // First, add a temporary outline structure at the top of the class, below other property declarations
    // This is a simple struct to track outline data during streaming without using CoreData
    private struct TempOutline {
        var summary: String = "Building outline..."
        var period: String = "Calculating..."
        var startDate: Date = Date()
        var endDate: Date = Date().addingTimeInterval(7 * 24 * 60 * 60)
        var lineItems: [String] = ["Gathering items..."]
        var requestId: String = ""
    }
    
    // Use a dictionary of these temp outlines instead of CoreData objects during streaming
    private var activeOutlineData: [String: TempOutline] = [:]
    
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
        // First check if this is a progressive outline event
        if let data = chunk.data(using: .utf8) {
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let eventType = json["event"] as? String,
                   eventType.starts(with: "outline_"),
                   let eventData = json["data"] as? [String: Any] {
                    
                    print("DEBUG OUTLINE EVENT: Received event type: \(eventType)")
                    handleOutlineEvent(eventType: eventType, eventData: eventData)
                    return
                }
            } catch {
                print("DEBUG CHUNK: Not a JSON outline event, processing as normal text")
            }
        }
        
        // If not an outline event, process as normal text chunk
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
        print("DEBUG MESSAGE TYPE: Received message completion with text length: \(fullText.count)")
        print("DEBUG MESSAGE TEXT: First 100 chars: \(String(fullText.prefix(100)))")
        
        // Try to parse as JSON to determine message type
        if let data = fullText.data(using: .utf8) {
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("DEBUG MESSAGE TYPE: Message is valid JSON with keys: \(json.keys.joined(separator: ", "))")
                    
                    // Check for outline directly in the top-level JSON
                    if let outline = json["outline"] as? [String: Any] {
                        print("DEBUG MESSAGE TYPE: Found outline in top-level JSON")
                        processOutlineFromCompletion(outline)
                        return
                    }
                    
                    // First check if we have a nested JSON structure (from completion event)
                    if let fullTextString = json["full_text"] as? String,
                       fullTextString.count > 0 {
                        print("DEBUG MESSAGE TYPE: Found full_text string with length: \(fullTextString.count)")
                        print("DEBUG MESSAGE TYPE: Full_text first 100 chars: \(String(fullTextString.prefix(100)))")
                        
                        // Try to parse the nested full_text as JSON
                        if let fullTextData = fullTextString.data(using: .utf8) {
                            do {
                                if let fullTextJson = try JSONSerialization.jsonObject(with: fullTextData) as? [String: Any] {
                                    print("DEBUG MESSAGE TYPE: Found nested JSON in full_text with keys: \(fullTextJson.keys.joined(separator: ", "))")
                                    
                                    // Check for outline data in the nested JSON
                                    if let outline = fullTextJson["outline"] as? [String: Any] {
                                        print("DEBUG MESSAGE TYPE: Found outline in nested JSON")
                                        processOutlineFromCompletion(outline)
                                        return
                                    } else if let needsChecklist = fullTextJson["needs_checklist"] as? Bool, needsChecklist == true {
                                        print("DEBUG MESSAGE TYPE: Found needs_checklist=true but no outline field. Looking for outline key...")
                                        
                                        // Print all the keys to help debug
                                        for (key, value) in fullTextJson {
                                            print("DEBUG JSON KEY: \(key) = \(type(of: value))")
                                        }
                                        
                                        // Completion messages might have the outline at the top level
                                        processCompletedMessage(fullTextJson)
                                    } else {
                                        // Handle other JSON formats in the nested structure
                                        processCompletedMessage(fullTextJson)
                                    }
                                } else {
                                    print("DEBUG MESSAGE TYPE: JSONSerialization returned nil for fullTextJson")
                                }
                            } catch {
                                print("DEBUG MESSAGE TYPE: Error parsing full_text as JSON: \(error)")
                                completeMessageWithText(fullTextString)
                            }
                        } else {
                            print("DEBUG MESSAGE TYPE: full_text doesn't contain valid JSON, treating as text")
                            completeMessageWithText(fullTextString)
                        }
                    } else {
                        // Process the direct JSON
                        if json["outline"] != nil {
                            print("DEBUG MESSAGE TYPE: This is a direct OUTLINE message")
                            processCompletedMessage(json)
                        } else if json["checklist_data"] != nil {
                            print("DEBUG MESSAGE TYPE: This is a CHECKLIST message")
                            processCompletedMessage(json)
                        } else if json["event"] as? String == "DONE" {
                            print("DEBUG MESSAGE TYPE: This is a DONE event without full_text")
                            completeMessageWithText(currentStreamingMessage?.content ?? "")
                        } else {
                            print("DEBUG MESSAGE TYPE: This is a JSON message but not an outline or checklist")
                            processCompletedMessage(json)
                        }
                    }
                }
            } catch {
                print("DEBUG MESSAGE TYPE: Message is not valid JSON, treating as normal message")
                completeMessageWithText(fullText)
            }
        } else {
            print("DEBUG MESSAGE TYPE: Could not convert message to data, treating as normal message")
            completeMessageWithText(fullText)
        }
    }
    
    // Add this helper method to process outlines from completion messages
    private func processOutlineFromCompletion(_ outline: [String: Any]) {
        print("DEBUG OUTLINE: Processing outline from completion event")
        
        // Create a new message or use existing streaming message
        let message: StreamingChatMessage
        if let currentMessage = currentStreamingMessage {
            message = currentMessage
        } else {
            message = StreamingChatMessageFactory.createOutlineBuildingMessage()
            messages.append(message)
        }
        
        // Set the message to building outline state to show the special UI
        message.isBuildingOutline = true
        message.content = "Creating your outline..."
        
        // Create an outline model
        if let outlineModel = createOutlineModel(from: outline) {
            // Attach the outline to the message right away, but keep in building state
            message.outline = outlineModel
            
            // Simulate progressive building by showing UI for a moment
            // This makes the outline appear to build itself even though we got the whole thing at once
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                // Update the message
                message.markAsComplete()
                message.isBuildingOutline = false
                message.content = "I've created an outline for you. Let me know if you'd like to proceed with the detailed checklists."
                print("DEBUG OUTLINE: Successfully applied outline to message")
                
                // Reset state
                self.isLoading = false
                self.isStreaming = false
                self.currentStreamingMessage = nil
            }
        } else {
            // Fallback if outline creation failed
            message.markAsComplete()
            message.isBuildingOutline = false
            message.content = "I've prepared a plan for you, but there was an issue with the outline formatting. Let me know if you'd like me to try again."
            print("DEBUG OUTLINE: Failed to create outline model")
            
            // Reset state
            isLoading = false
            isStreaming = false
            currentStreamingMessage = nil
        }
        
        // Increment unread count if not expanded
        if !isExpanded {
            unreadCount += 1
        }
    }
    
    // Helper method to process the completed message data
    private func processCompletedMessage(_ json: [String: Any]) {
        print("DEBUG PROCESS: Processing completed message with keys: \(json.keys.joined(separator: ", "))")
        
        // Check for needs_checklist flag
        if let needsChecklist = json["needs_checklist"] as? Bool, needsChecklist == true {
            print("DEBUG PROCESS: Found needs_checklist=true, looking for outline data")
            
            // Handle direct outline data
            if let outline = json["outline"] as? [String: Any] {
                print("DEBUG PROCESS: Found outline directly in the JSON")
                processOutlineData(outline)
                return
            }
            
            // Try to reconstruct outline from data in the message
            let responseText = "I've created an outline for you. Let me know if you'd like to proceed with the detailed checklists."
            
            var outlineData: [String: Any] = [:]
            
            // Try to extract potential outline fields
            if let summary = json["summary"] as? String {
                outlineData["summary"] = summary
            } else if let title = json["title"] as? String {
                outlineData["summary"] = title
            }
            
            // Extract period if available
            if let period = json["period"] as? String {
                outlineData["period"] = period
            } else if let timePeriod = json["time_period"] as? String {
                outlineData["period"] = timePeriod
            }
            
            // Extract dates if available
            if let startDate = json["start_date"] as? String {
                outlineData["start_date"] = startDate
            }
            
            if let endDate = json["end_date"] as? String {
                outlineData["end_date"] = endDate
            }
            
            // Extract line items if available in any format
            if let lineItems = json["line_items"] as? [String] {
                outlineData["line_items"] = lineItems
            } else if let lineItems = json["line_item"] as? [String] {
                outlineData["line_items"] = lineItems
            } else if let items = json["items"] as? [String] {
                outlineData["line_items"] = items
            } else if let tasks = json["tasks"] as? [String] {
                outlineData["line_items"] = tasks
            }
            
            // If we have enough data to create an outline
            if !outlineData.isEmpty {
                print("DEBUG PROCESS: Created synthetic outline from message data")
                processOutlineData(outlineData)
                return
            } else {
                print("DEBUG PROCESS: Could not extract outline data, treating as regular message")
            }
        }
        
        // Handle outline data
        else if let outline = json["outline"] as? [String: Any] {
            print("DEBUG PROCESS: Processing outline data directly")
            processOutlineData(outline)
            return
        }
        
        // Handle regular message data (fallback)
        let messageText: String
        if let response = json["response"] as? String {
            messageText = response
        } else if let chunk = json["chunk"] as? String {
            messageText = chunk
        } else {
            messageText = "I've processed your request."
        }
        
        completeMessageWithText(messageText)
    }
    
    private func processOutlineData(_ outline: [String: Any]) {
        print("DEBUG OUTLINE PROCESS: Processing outline data with keys: \(outline.keys.joined(separator: ", "))")
        
        // Text response to show
        let responseText = "I've created an outline for you. Let me know if you'd like to proceed with the detailed checklists."
        
        // Create outline model and update current message
        if let outlineModel = createOutlineModel(from: outline) {
            if let currentMessage = currentStreamingMessage {
                currentMessage.markAsComplete()
                currentMessage.outline = outlineModel
                currentMessage.replaceContent(with: responseText)
                print("DEBUG PROCESS: Successfully applied outline to message")
            } else {
                // Create a new message if needed
                let newMessage = StreamingChatMessageFactory.createOutlineMessage(content: responseText, outline: outlineModel)
            messages.append(newMessage)
                print("DEBUG PROCESS: Created new message with outline")
            }
        } else {
            // Fallback to plain text if outline creation failed
            completeMessageWithText(responseText)
            print("DEBUG PROCESS: Failed to create outline model")
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
    
    // Helper method to complete a message with plain text
    private func completeMessageWithText(_ text: String) {
        if let currentMessage = currentStreamingMessage {
            currentMessage.markAsComplete()
            currentMessage.replaceContent(with: text)
        } else if !text.isEmpty {
            // Create a new complete message if we don't have one
            let newMessage = StreamingChatMessageFactory.createCompleteAssistantMessage(content: text)
            messages.append(newMessage)
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
        // Print the outline data for debugging
        print("DEBUG OUTLINE: Got outline data with keys: \(outlineData.keys.joined(separator: ", "))")
        
        // Get the managed object context from ChatPersistenceService
        let context = ChatPersistenceService.shared.viewContext
        
        // Create a new ChecklistOutline entity
        let outline = ChecklistOutline(context: context)
        outline.id = UUID()
        outline.timestamp = Date()
        outline.isDone = false  // Mark as not done initially
        
        // Extract data from the outline JSON
        if let summary = outlineData["summary"] as? String {
            outline.summary = summary
            print("DEBUG OUTLINE: Set summary: \(summary)")
        } else if let summary = outlineData["title"] as? String {
            // Alternative key that might be used
            outline.summary = summary
            print("DEBUG OUTLINE: Set summary from title: \(summary)")
        } else {
            print("DEBUG OUTLINE: Missing summary in outline data")
            outline.summary = "Task outline"
        }
        
        if let period = outlineData["period"] as? String {
            outline.period = period
            print("DEBUG OUTLINE: Set period: \(period)")
        } else if let period = outlineData["time_period"] as? String {
            // Alternative key that might be used
            outline.period = period
            print("DEBUG OUTLINE: Set period from time_period: \(period)")
        } else {
            print("DEBUG OUTLINE: Missing period in outline data")
            outline.period = "Unspecified period"
        }
        
        // Extract dates using DateFormatter
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        // Set default dates (today and a week from today)
        let today = Date()
        outline.startDate = today
        outline.endDate = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today
        
        if let startDateStr = outlineData["start_date"] as? String,
           let startDate = dateFormatter.date(from: startDateStr) {
            outline.startDate = startDate
            print("DEBUG OUTLINE: Set start date: \(startDateStr)")
        } else if let startDateStr = outlineData["startDate"] as? String,
                 let startDate = dateFormatter.date(from: startDateStr) {
            // Alternative key that might be used
            outline.startDate = startDate
            print("DEBUG OUTLINE: Set start date from startDate: \(startDateStr)")
        } else {
            print("DEBUG OUTLINE: Missing or invalid start_date in outline data, using today")
        }
        
        if let endDateStr = outlineData["end_date"] as? String,
           let endDate = dateFormatter.date(from: endDateStr) {
            outline.endDate = endDate
            print("DEBUG OUTLINE: Set end date: \(endDateStr)")
        } else if let endDateStr = outlineData["endDate"] as? String,
                 let endDate = dateFormatter.date(from: endDateStr) {
            // Alternative key that might be used
            outline.endDate = endDate
            print("DEBUG OUTLINE: Set end date from endDate: \(endDateStr)")
        } else {
            print("DEBUG OUTLINE: Missing or invalid end_date in outline data, using today + 7 days")
        }
        
        // Extract line items - try multiple possible formats
        var lineItems: [String] = []
        
        // Try details array format
        if let details = outlineData["details"] as? [[String: Any]] {
            print("DEBUG OUTLINE: Found details array with \(details.count) items")
            for detail in details {
                if let title = detail["title"] as? String {
                    if let breakdown = detail["breakdown"] as? String {
                    lineItems.append("\(title): \(breakdown)")
                    } else {
                        lineItems.append(title)
                    }
                }
            }
        } 
        // Try line_items array format (plural)
        else if let items = outlineData["line_items"] as? [String] {
            print("DEBUG OUTLINE: Found line_items array with \(items.count) items")
            lineItems = items
        }
        // Try line_item array format (singular)
        else if let items = outlineData["line_item"] as? [String] {
            print("DEBUG OUTLINE: Found line_item array with \(items.count) items")
            lineItems = items
        }
        // Try items array format (alternative)
        else if let items = outlineData["items"] as? [String] {
            print("DEBUG OUTLINE: Found items array with \(items.count) items")
            lineItems = items
        }
        // Try tasks array format (alternative)
        else if let items = outlineData["tasks"] as? [String] {
            print("DEBUG OUTLINE: Found tasks array with \(items.count) items")
            lineItems = items
        }
        
        if lineItems.isEmpty {
            print("DEBUG OUTLINE: Could not find any line items in outline data, adding placeholder")
            lineItems = ["No details available"]
        } else {
            print("DEBUG OUTLINE: Set \(lineItems.count) line items")
        }
        
        outline.lineItem = lineItems as NSArray
        
        // Save the context
        do {
            try context.save()
            print("DEBUG OUTLINE: Successfully created outline model with ID: \(outline.id)")
            return outline
        } catch {
            print("DEBUG OUTLINE: Error saving CoreData outline: \(error)")
            return nil
        }
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
    
    // Add this new method to handle outline events
    private func handleOutlineEvent(eventType: String, eventData: [String: Any]) {
        print("DEBUG OUTLINE EVENT: Processing \(eventType) with keys: \(eventData.keys.joined(separator: ", "))")
        
        // Get the request ID from the event data
        guard let requestId = eventData["request_id"] as? String else {
            print("DEBUG OUTLINE EVENT: Missing request_id, unable to process event")
            return
        }
        
        // Initialize the outline if it doesn't exist yet or if it's a start event
        if eventType == "outline_start" || activeOutlines[requestId] == nil {
            if eventType == "outline_start" {
                print("DEBUG OUTLINE EVENT: Starting new outline for request \(requestId)")
                
                // Create a new message for the outline if needed
                if currentStreamingMessage == nil || !currentStreamingMessage!.isBuildingOutline {
                    let newMessage = StreamingChatMessageFactory.createOutlineBuildingMessage()
                    messages.append(newMessage)
                    currentStreamingMessage = newMessage
                    isStreaming = true
                }
                
                // Instead of creating a CoreData object, use temporary properties
                currentStreamingMessage?.outlineSummary = "Building outline..."
                currentStreamingMessage?.outlinePeriod = "Calculating..."
                currentStreamingMessage?.outlineStartDate = Date()
                currentStreamingMessage?.outlineEndDate = Date().addingTimeInterval(7 * 24 * 60 * 60) // Default 1 week
                currentStreamingMessage?.outlineLineItems = ["Gathering items..."]
                
                // Store the request ID for tracking
                currentOutlineRequestId = requestId
                
                // Ensure the message is marked as building an outline
                currentStreamingMessage?.isBuildingOutline = true
                currentStreamingMessage?.content = "Starting to create your outline..."
            }
        }
        
        // Process each event type - updating temporary properties during streaming
        switch eventType {
        case "outline_summary":
            if let summary = eventData["summary"] as? String {
                // Update the temporary property instead of a CoreData object
                currentStreamingMessage?.outlineSummary = summary
                currentStreamingMessage?.content = "Creating outline: \(summary)..."
            }
            
        case "outline_period":
            if let period = eventData["period"] as? String {
                // Update the temporary property
                currentStreamingMessage?.outlinePeriod = period
                currentStreamingMessage?.content = "Creating a \(period) outline..."
            }
            
        case "outline_date":
            // Update the temporary start and end date properties
            if let startDateString = eventData["start_date"] as? String,
               let startDate = ISO8601DateFormatter().date(from: startDateString) {
                currentStreamingMessage?.outlineStartDate = startDate
            }
            
            if let endDateString = eventData["end_date"] as? String,
               let endDate = ISO8601DateFormatter().date(from: endDateString) {
                currentStreamingMessage?.outlineEndDate = endDate
            }
            
            // Update content to show progress
            let startDateString = currentStreamingMessage?.outlineStartDate?.formatted(date: .abbreviated, time: .omitted) ?? "today"
            let endDateString = currentStreamingMessage?.outlineEndDate?.formatted(date: .abbreviated, time: .omitted) ?? "next week"
            currentStreamingMessage?.content = "Creating outline from \(startDateString) to \(endDateString)..."
            
        case "outline_detail":
            // Fix: Handle detail as a dictionary containing title and breakdown fields
            if let detailDict = eventData["detail"] as? [String: Any],
               let title = detailDict["title"] as? String {
                
                // Initialize or clear the line items array if this is the first item
                if currentStreamingMessage?.outlineLineItems.isEmpty ?? true || 
                   currentStreamingMessage?.outlineLineItems == ["Gathering items..."] {
                    // Clear the placeholder if this is the first item
                    currentStreamingMessage?.outlineLineItems = []
                }
                
                // Format the detail with title and breakdown (if available)
                var formattedDetail = title
                if let breakdown = detailDict["breakdown"] as? String {
                    formattedDetail = "\(title): \(breakdown)"
                }
                
                // Add the new line item
                currentStreamingMessage?.outlineLineItems.append(formattedDetail)
                
                // Update the content to show progress
                let itemCount = currentStreamingMessage?.outlineLineItems.count ?? 0
                currentStreamingMessage?.content = "Building outline with \(itemCount) items..."
                
                // Print debug info
                print("DEBUG OUTLINE DETAIL: Added item '\(formattedDetail)' to outline")
            } else {
                print("DEBUG OUTLINE DETAIL: Failed to parse detail dictionary or missing title")
            }
            
        case "outline_complete":
            if let outline = eventData["outline"] as? [String: Any] {
                // Use the persistence service's view context to create the Core Data object
                let context = ChatPersistenceService.shared.viewContext
                let outlineModel = ChecklistOutline(context: context)
                
                // Set the ID properly
                outlineModel.id = UUID()
                outlineModel.timestamp = Date()
                
                // Set properties from the complete outline data
                if let summary = outline["summary"] as? String {
                    outlineModel.summary = summary
                } else {
                    outlineModel.summary = currentStreamingMessage?.outlineSummary ?? "Checklist"
                }
                
                if let period = outline["period"] as? String {
                    outlineModel.period = period
                } else {
                    outlineModel.period = currentStreamingMessage?.outlinePeriod ?? "Daily"
                }
                
                // Parse dates if available in the outline
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                
                if let startDateStr = outline["start_date"] as? String,
                   let startDate = dateFormatter.date(from: startDateStr) {
                    outlineModel.startDate = startDate
                } else {
                    outlineModel.startDate = currentStreamingMessage?.outlineStartDate ?? Date()
                }
                
                if let endDateStr = outline["end_date"] as? String,
                   let endDate = dateFormatter.date(from: endDateStr) {
                    outlineModel.endDate = endDate
                } else {
                    outlineModel.endDate = currentStreamingMessage?.outlineEndDate ?? Date().addingTimeInterval(7 * 24 * 60 * 60)
                }
                
                // Create line items from details if available
                var lineItems: [String] = []
                if let details = outline["details"] as? [[String: Any]] {
                    for detail in details {
                        if let title = detail["title"] as? String {
                            if let breakdown = detail["breakdown"] as? String {
                                lineItems.append("\(title): \(breakdown)")
                            } else {
                                lineItems.append(title)
                            }
                        }
                    }
                }
                
                // Use our accumulated line items if we have them
                if lineItems.isEmpty && !(currentStreamingMessage?.outlineLineItems.isEmpty ?? true) {
                    lineItems = currentStreamingMessage?.outlineLineItems ?? []
                }
                
                // Ensure we have at least one item
                if lineItems.isEmpty {
                    lineItems = ["No items"]
                }
                
                outlineModel.lineItem = lineItems as NSArray
                
                // Save the context
                do {
                    try context.save()
                    print("DEBUG OUTLINE: Successfully saved CoreData outline with ID: \(outlineModel.id)")
                } catch {
                    print("DEBUG OUTLINE: Error saving CoreData outline: \(error)")
                }
                
                // Update the streaming message with the created outline
                currentStreamingMessage?.checklistOutline = outlineModel
                currentStreamingMessage?.isBuildingOutline = false
                currentStreamingMessage?.content = "Your outline is ready!"
                
                // Reset streaming state
                isStreaming = false
                currentStreamingMessage = nil
                currentOutlineRequestId = nil
                
                // Call the completion handler
                outlineCompletionHandler?(nil)
            } else {
                print("DEBUG OUTLINE COMPLETE: Failed to find outline in completion data")
            }
            
        case "outline_error":
            print("DEBUG OUTLINE EVENT: Outline error for request \(requestId)")
            
            // Set error message
            if let errorMessage = eventData["error"] as? String {
                currentStreamingMessage?.content = "Error creating outline: \(errorMessage)"
            } else {
                currentStreamingMessage?.content = "Error creating outline. Please try again."
            }
            
            // Complete the message and mark as error
            currentStreamingMessage?.markAsComplete()
            currentStreamingMessage?.isBuildingOutline = false
            isStreaming = false
            isLoading = false
            
            // Clean up
            currentStreamingMessage = nil
            activeOutlines.removeValue(forKey: requestId)
            currentOutlineRequestId = nil
            
        default:
            print("DEBUG OUTLINE EVENT: Unknown outline event type: \(eventType)")
        }
    }
    
    // Helper method to create a CoreData outline from the temporary properties
    private func createOutlineModelFromTemp() -> ChecklistOutline? {
        guard let message = currentStreamingMessage else {
            return nil
        }
        
        // Get the managed object context from ChatPersistenceService
        let context = ChatPersistenceService.shared.viewContext
        
        // Create a new CoreData outline object
        let outline = ChecklistOutline(context: context)
        outline.id = UUID()
        outline.timestamp = Date()
        outline.isDone = false
        
        // Copy data from temporary properties
        outline.summary = message.outlineSummary ?? "Task outline"
        outline.period = message.outlinePeriod ?? "Unspecified period"
        outline.startDate = message.outlineStartDate ?? Date()
        outline.endDate = message.outlineEndDate ?? Date().addingTimeInterval(7 * 24 * 60 * 60)
        outline.lineItem = message.outlineLineItems.isEmpty ? 
            ["No details available"] as NSArray : 
            message.outlineLineItems as NSArray
        
        // Save the context
        do {
            try context.save()
            print("DEBUG OUTLINE: Successfully saved CoreData outline with ID: \(outline.id)")
            return outline
        } catch {
            print("DEBUG OUTLINE: Error saving CoreData outline: \(error)")
            return nil
        }
    }
} 
