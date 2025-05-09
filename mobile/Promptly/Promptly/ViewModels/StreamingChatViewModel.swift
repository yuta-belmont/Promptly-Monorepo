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
    @Published var shouldScrollToBottom: Bool = false
    
    // Add debounce timer property
    private var scrollDebounceTimer: Timer?
    private let scrollDebounceInterval: TimeInterval = 0.1
    private var lastScrollTime: Date?
    
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
    
    // Add this at the top of the class with other properties
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    // Add haptic feedback generator
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    // Private initializer for singleton pattern
    private init() {
        setupCallbacks()
        // Prepare the haptic generator
        hapticGenerator.prepare()
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
    
    // Send a pre-created message
    func sendMessage(_ message: StreamingChatMessage) {
        // Check if user is authenticated
        guard authManager.isAuthenticated && !authManager.isGuestUser else {
            return
        }
        
        // Add the user message
        messages.append(message)
        
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
                    content: message.content,
                    messageHistory: context
                )
            } catch {
                // Handle send error
                handleError(error)
            }
        }
    }
    
    // Keep the old method for backward compatibility
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
            } catch {
                // Handle send error
                handleError(error)
            }
        }
    }
    
    // Add debounced scroll method
    private func debouncedScrollToBottom() {
        // If we haven't scrolled in the last 0.1 seconds, scroll now
        if lastScrollTime == nil || Date().timeIntervalSince(lastScrollTime!) > scrollDebounceInterval {
            shouldScrollToBottom = true
            lastScrollTime = Date()
        } else if scrollDebounceTimer == nil {
            // Only schedule a delayed scroll if we don't already have one pending
            scrollDebounceTimer = Timer.scheduledTimer(withTimeInterval: scrollDebounceInterval, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.shouldScrollToBottom = true
                    self?.lastScrollTime = Date()
                    self?.scrollDebounceTimer = nil
                }
            }
        }
    }
    
    // Handle received chunk during streaming
    private func handleChunkReceived(_ chunk: String) {
        
        // Try to parse the JSON data
        if let data = chunk.data(using: .utf8) {
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let eventType = json["event"] as? String {
                    
                    // Route based on event type
                    switch eventType {
                    case "DONE":
                        if let fullText = json["full_text"] as? String {
                            handleMessageCompleted(fullText)
                        }
                        return
                        
                    case let type where type.starts(with: "outline_"):
                        if let eventData = json["data"] as? [String: Any] {
                            Task {
                                await handleOutlineEvent(eventType: type, eventData: eventData)
                                debouncedScrollToBottom()
                            }
                        }
                        return
                        
                    case let type where type.starts(with: "checklist_"):
                        if let eventData = json["data"] as? [String: Any] {
                            handleChecklistEvent(eventType: type, eventData: eventData)
                            debouncedScrollToBottom()
                        }
                        return
                        
                    default:
                        // If it's a JSON message but not a known event type, append as normal
                        appendChunkToMessage(chunk)
                    }
                } else {
                    // If JSON parsing succeeded but no event type, append as normal
                    appendChunkToMessage(chunk)
                }
            } catch {
                // If JSON parsing failed, append as normal text
                appendChunkToMessage(chunk)
            }
        } else {
            // If data conversion failed, append as normal text
            appendChunkToMessage(chunk)
        }
    }
    
    // Helper method to append chunk to message
    private func appendChunkToMessage(_ chunk: String) {
        if let currentMessage = currentStreamingMessage {
            // Append the chunk to the current message
            currentMessage.appendContent(chunk)
            // Use debounced scroll for text chunks
            debouncedScrollToBottom()
            // Force UI update
            objectWillChange.send()
        } else {
            // If we don't have a streaming message, create one
            let newMessage = StreamingChatMessageFactory.createAssistantMessage()
            newMessage.appendContent(chunk)
            messages.append(newMessage)
            currentStreamingMessage = newMessage
            isStreaming = true
            // Use debounced scroll for new messages
            debouncedScrollToBottom()
            // Force UI update
            objectWillChange.send()
        }
    }
    
    // Handle message completion
    private func handleMessageCompleted(_ fullText: String) {
        print("🔍 StreamingChatViewModel.handleMessageCompleted(fullText: \(fullText.prefix(50))...)")
        // Early handling of empty strings (disconnection events)
        if fullText.isEmpty {
            return
        }
        
        if let currentMessage = currentStreamingMessage {
            
            // If we already have a completed outline, skip processing
            if currentMessage.checklistOutline != nil {
                return
            }
            
            // Try to parse as JSON to determine message type
            if let data = fullText.data(using: .utf8) {
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Check for outline directly in the top-level JSON
                        if let outline = json["outline"] as? [String: Any] {
                            createAndAttachOutline(to: currentMessage, from: outline)
                            // Trigger haptic feedback for outline completion
                            self.hapticGenerator.impactOccurred()
                            return
                        }
                        
                        // Check for response_text field in the JSON
                        if let responseText = json["response_text"] as? String {
                            currentMessage.markAsComplete()
                            currentMessage.replaceContent(with: responseText)
                            // Trigger haptic feedback for message completion with delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.hapticGenerator.impactOccurred()
                            }
                            objectWillChange.send()
                            return
                        }
                        
                        // Process other JSON formats
                        if json["outline"] != nil {
                            processCompletedMessage(json)
                        } else if json["checklist_data"] != nil {
                            processCompletedMessage(json)
                        } else if json["event"] as? String == "DONE" {
                            currentMessage.markAsComplete()
                            currentMessage.replaceContent(with: currentMessage.content)
                            objectWillChange.send()
                        } else {
                            processCompletedMessage(json)
                        }
                    }
                } catch {
                    // Only process as direct text if we haven't already handled an outline
                    if !currentMessage.isBuildingOutline {
                        currentMessage.markAsComplete()
                        currentMessage.replaceContent(with: fullText)
                        // Trigger haptic feedback for direct text completion with delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.hapticGenerator.impactOccurred()
                        }
                        objectWillChange.send()
                    }
                    
                    // Reset streaming state
                    isStreaming = false
                    currentStreamingMessage = nil
                }
            }
        }
    }
    
    // Add this helper method to process outlines from completion messages
    private func processOutlineFromCompletion(_ outline: [String: Any]) {
        print("🔍 StreamingChatViewModel.processOutlineFromCompletion(outline: \(outline))")
        // Only proceed if we have a current streaming message
        guard let currentMessage = currentStreamingMessage else {
            return
        }
        
        // Create and attach the outline
        createAndAttachOutline(to: currentMessage, from: outline)
    }
    
    // Helper method to process the completed message data
    private func processCompletedMessage(_ json: [String: Any]) {
        print("🔍 StreamingChatViewModel.processCompletedMessage(json: \(json))")
        
        // Check for needs_checklist flag
        if let needsChecklist = json["needs_checklist"] as? Bool, needsChecklist == true {
            
            // Handle direct outline data
            if let outline = json["outline"] as? [String: Any] {
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
                processOutlineData(outlineData)
                return
            }
        }
        
        // Handle outline data
        else if let outline = json["outline"] as? [String: Any] {
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
        
        // Text response to show
        let responseText = "I've created an outline for you. Let me know if you'd like to proceed with the detailed checklists."
        
        // Create outline model and update current message
        if let outlineModel = createOutlineModel(from: outline) {
            if let currentMessage = currentStreamingMessage {
                currentMessage.markAsComplete()
                currentMessage.outlineSummary = outlineModel.summary
                currentMessage.outlinePeriod = outlineModel.period
                currentMessage.outlineStartDate = outlineModel.startDate
                currentMessage.outlineEndDate = outlineModel.endDate
                currentMessage.outlineLineItems = outlineModel.lineItem as? [String] ?? []
                currentMessage.replaceContent(with: responseText)
            } else {
                // Create a new message if needed
                let newMessage = StreamingChatMessageFactory.createOutlineMessage(content: responseText, outline: outlineModel)
            messages.append(newMessage)
            }
        } else {
            // Fallback to plain text if outline creation failed
            completeMessageWithText(responseText)
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
            
            // Force UI update
            objectWillChange.send()
        } else if !text.isEmpty {
            let newMessage = StreamingChatMessageFactory.createCompleteAssistantMessage(content: text)
            messages.append(newMessage)
            
            // Force UI update
            objectWillChange.send()
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
        } else if let summary = outlineData["title"] as? String {
            // Alternative key that might be used
            outline.summary = summary
        } else {
            outline.summary = "Task outline"
        }
        
        // Try to parse start date from various possible formats
        if let startDateStr = outlineData["start_date"] as? String,
           let startDate = dateFormatter.date(from: startDateStr) {
            outline.startDate = startDate
        }
        
        // Try to parse end date from various possible formats
        if let endDateStr = outlineData["end_date"] as? String,
           let endDate = dateFormatter.date(from: endDateStr) {
            outline.endDate = endDate
        }
        
        // Extract line items - try multiple possible formats
        var lineItems: [String] = []
        
        // Try details array format
        if let details = outlineData["details"] as? [[String: Any]] {
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
            lineItems = items
        }
        // Try line_item array format (singular)
        else if let items = outlineData["line_item"] as? [String] {
            lineItems = items
        }
        // Try items array format (alternative)
        else if let items = outlineData["items"] as? [String] {
            lineItems = items
        }
        // Try tasks array format (alternative)
        else if let items = outlineData["tasks"] as? [String] {
            lineItems = items
        }
        
        if lineItems.isEmpty {
            lineItems = ["No details available"]
        }
        
        outline.lineItem = lineItems as NSArray
        
        // Save the context
        do {
            try context.save()
            return outline
        } catch {
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
    
    // Check if there's a pending outline
    var hasPendingOutline: Bool {
        return messages.contains { message in
            message.checklistOutline?.isDone == false
        }
    }
    
    // Accept outline
    func acceptOutline() {
        if let message = messages.last(where: { $0.checklistOutline != nil }),
           let outline = message.checklistOutline {
            // Trigger haptic feedback, remove input buttons
            outline.isDone = true //this removes input buttons
            objectWillChange.send()
            hapticGenerator.impactOccurred()
            
            // Prepare outline data
            let outlineData: [String: Any] = [
                "summary": outline.summary ?? "",
                "period": outline.period ?? "",
                "start_date": outline.startDate?.ISO8601Format() ?? "",
                "end_date": outline.endDate?.ISO8601Format() ?? "",
                "details": (outline.lineItem as? [String])?.map { ["title": $0] } ?? []
            ]
            
            // Send outline acceptance request
            Task {
                do {
                    _ = try await pubSubChatService.sendOutlineRequest(
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
        if let message = messages.last(where: { $0.checklistOutline != nil }),
           let outline = message.checklistOutline {
            // Trigger haptic feedback
            hapticGenerator.impactOccurred()
            
            outline.isDone = true
            // Notify UI of state change
            objectWillChange.send()
        }
    }
    
    // Add this new method to handle outline events
    private func handleOutlineEvent(eventType: String, eventData: [String: Any]) async {
        print("🔍 StreamingChatViewModel.handleOutlineEvent(eventType: \(eventType), eventData: \(eventData))")
        // Get the request ID from the event data
        guard let requestId = eventData["request_id"] as? String else {
            return
        }
        
        // Initialize the outline if it doesn't exist yet or if it's a start event
        if eventType == "outline_start" || activeOutlines[requestId] == nil {
            if eventType == "outline_start" {
                // Update the current streaming message instead of creating a new one
                if let currentMessage = currentStreamingMessage {
                    // Update the existing message to be an outline building message
                    currentMessage.isBuildingOutline = true
                    currentMessage.outlineSummary = "Building outline..."
                    currentMessage.outlinePeriod = "Calculating..."
                    currentMessage.outlineLineItems = ["Gathering items..."]
                    currentMessage.content = "Starting to create your outline..."
                    
                    // Store the request ID for tracking
                    currentOutlineRequestId = requestId
                    
                    // Ensure streaming state is properly set
                    isStreaming = true
                    currentMessage.isStreaming = true
                }
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
            
        case "outline_dates":
            // Update the temporary start and end date properties
            if let startDateString = eventData["start_date"] as? String,
               let startDate = dateFormatter.date(from: startDateString) {
                currentStreamingMessage?.outlineStartDate = startDate
            }
            
            if let endDateString = eventData["end_date"] as? String,
               let endDate = dateFormatter.date(from: endDateString) {
                currentStreamingMessage?.outlineEndDate = endDate
            }
            
            // Update content to show progress
            if let startDate = currentStreamingMessage?.outlineStartDate,
               let endDate = currentStreamingMessage?.outlineEndDate {
                let startDateString = startDate.formatted(date: .abbreviated, time: .omitted)
                let endDateString = endDate.formatted(date: .abbreviated, time: .omitted)
                currentStreamingMessage?.content = "Creating outline from \(startDateString) to \(endDateString)..."
            } else {
                currentStreamingMessage?.content = "Calculating date range..."
            }
            
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
            }
            
        case "outline_complete":
            if let outlineData = eventData["outline"] as? [String: Any],
               let outline = outlineData["outline"] as? [String: Any] {
                // Create a new CoreData outline object
                let context = ChatPersistenceService.shared.viewContext
                let outlineModel = ChecklistOutline(context: context)
                outlineModel.id = UUID()
                outlineModel.timestamp = Date()
                outlineModel.isDone = false
                
                // Extract and set the outline data
                if let summary = outline["summary"] as? String {
                    outlineModel.summary = summary
                }
                
                if let period = outline["period"] as? String {
                    outlineModel.period = period
                }
                
                // Parse dates
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                
                if let startDateStr = outline["start_date"] as? String,
                   let startDate = dateFormatter.date(from: startDateStr) {
                    outlineModel.startDate = startDate
                }
                
                if let endDateStr = outline["end_date"] as? String,
                   let endDate = dateFormatter.date(from: endDateStr) {
                    outlineModel.endDate = endDate
                }
                
                // Extract line items from details
                if let details = outline["details"] as? [[String: Any]] {
                    var lineItems: [String] = []
                    for detail in details {
                        if let title = detail["title"] as? String {
                            if let breakdown = detail["breakdown"] as? String {
                                lineItems.append("\(title): \(breakdown)")
                            } else {
                                lineItems.append(title)
                            }
                        }
                    }
                    outlineModel.lineItem = lineItems as NSArray
                }
                
                // Save the context
                do {
                    try context.save()
                    
                    // Batch all UI updates together
                    await MainActor.run {
                        if let currentMessage = currentStreamingMessage {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                // Update message state
                                currentMessage.checklistOutline = outlineModel
                                currentMessage.isBuildingOutline = false
                                currentMessage.markAsComplete()
                                currentMessage.content = eventData["message"] as? String ?? "I've created an outline for you. Let me know if you'd like to proceed with the detailed checklists."
                                
                                // Trigger haptic feedback
                                hapticGenerator.impactOccurred()
                                
                                // Reset streaming state
                                isStreaming = false
                                currentStreamingMessage = nil
                                currentOutlineRequestId = nil
                            }
                        }
                        
                        // Close the SSE connection after UI updates
                        pubSubChatService.cleanup()
                        
                        // Call the completion handler
                        outlineCompletionHandler?(nil)
                    }
                } catch {
                    print("DEBUG OUTLINE: Error saving CoreData outline: \(error)")
                    
                    // Batch fallback UI updates
                    await MainActor.run {
                        if let currentMessage = currentStreamingMessage {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                // Update with temporary properties
                                currentMessage.outlineSummary = outline["summary"] as? String ?? "Task outline"
                                currentMessage.outlinePeriod = outline["period"] as? String ?? "Unspecified period"
                                if let details = outline["details"] as? [[String: Any]] {
                                    var lineItems: [String] = []
                                    for detail in details {
                                        if let title = detail["title"] as? String {
                                            if let breakdown = detail["breakdown"] as? String {
                                                lineItems.append("\(title): \(breakdown)")
                                            } else {
                                                lineItems.append(title)
                                            }
                                        }
                                    }
                                    currentMessage.outlineLineItems = lineItems
                                }
                                currentMessage.isBuildingOutline = false
                                currentMessage.markAsComplete()
                                currentMessage.content = eventData["message"] as? String ?? "I've prepared a plan for you, but there was an issue with the outline formatting. Let me know if you'd like me to try again."
                                
                                // Reset streaming state
                                isStreaming = false
                                currentStreamingMessage = nil
                                currentOutlineRequestId = nil
                            }
                        }
                        
                        // Close the SSE connection after UI updates
                        pubSubChatService.cleanup()
                    }
                }
            } else {
                // Handle missing outline data
                await MainActor.run {
                    guard let message = currentStreamingMessage else {
                        outlineCompletionHandler?(nil)
                        return
                    }
                    
                    withAnimation(.easeInOut(duration: 0.3)) {
                        // Complete the message with existing data
                        message.isBuildingOutline = false
                        message.markAsComplete()
                        message.content = "Outline creation complete."
                        
                        // Reset streaming state
                        isStreaming = false
                        currentStreamingMessage = nil
                        currentOutlineRequestId = nil
                    }
                    
                    // Close the SSE connection after UI updates
                    pubSubChatService.cleanup()
                    
                    // Call the completion handler
                    outlineCompletionHandler?(nil)
                }
            }
            
        case "outline_error":
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
    
    private func handleStreamingMessage(_ message: StreamingChatMessage) {
        print("🔍 StreamingChatViewModel.handleStreamingMessage(message: \(message.id))")
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        }
    }
    
    private func handleStreamingComplete(_ message: StreamingChatMessage) {
        print("🔍 StreamingChatViewModel.handleStreamingComplete(message: \(message.id))")
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        }
    }
    
    // Add this new method to handle outline creation and message updates
    private func createAndAttachOutline(to message: StreamingChatMessage, from outline: [String: Any]) {
        print("🔍 StreamingChatViewModel.createAndAttachOutline(message: \(message.id), outline: \(outline))")
        // Create the CoreData outline object
        let context = ChatPersistenceService.shared.viewContext
        let outlineModel = ChecklistOutline(context: context)
        outlineModel.id = UUID()
        outlineModel.timestamp = Date()
        outlineModel.isDone = false
        
        // Extract data from the outline JSON
        if let summary = outline["summary"] as? String {
            outlineModel.summary = summary
        } else if let summary = outline["title"] as? String {
            outlineModel.summary = summary
        } else {
            outlineModel.summary = "Task outline"
        }
        
        if let period = outline["period"] as? String {
            outlineModel.period = period
        } else if let period = outline["time_period"] as? String {
            outlineModel.period = period
        } else {
            outlineModel.period = "Unspecified period"
        }
        
        // Extract dates using DateFormatter
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        // Set default dates (today and a week from today)
        let today = Date()
        outlineModel.startDate = today
        outlineModel.endDate = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today
        
        if let startDateStr = outline["start_date"] as? String,
           let startDate = dateFormatter.date(from: startDateStr) {
            outlineModel.startDate = startDate
        }
        
        if let endDateStr = outline["end_date"] as? String,
           let endDate = dateFormatter.date(from: endDateStr) {
            outlineModel.endDate = endDate
        }
        
        // Extract line items
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
        } else if let items = outline["line_items"] as? [String] {
            lineItems = items
        } else if let items = outline["line_item"] as? [String] {
            lineItems = items
        } else if let items = outline["items"] as? [String] {
            lineItems = items
        } else if let items = outline["tasks"] as? [String] {
            lineItems = items
        }
        
        if lineItems.isEmpty {
            lineItems = ["No details available"]
        }
        
        outlineModel.lineItem = lineItems as NSArray
        
        // Save the context
        do {
            try context.save()
            
            // Update the message with the completed outline
            message.checklistOutline = outlineModel
            message.isBuildingOutline = false
            message.markAsComplete()
            message.content = "I've created an outline for you. Let me know if you'd like to proceed with the detailed checklists."
            
            // Reset streaming state
            isStreaming = false
            currentStreamingMessage = nil
            
            // Increment unread count if not expanded
            if !isExpanded {
                unreadCount += 1
            }
        } catch {
            print("DEBUG OUTLINE: Error saving CoreData outline: \(error)")
            // Fallback to temporary properties if save fails
            message.outlineSummary = outline["summary"] as? String ?? "Task outline"
            message.outlinePeriod = outline["period"] as? String ?? "Unspecified period"
            message.outlineLineItems = lineItems
            message.isBuildingOutline = false
            message.markAsComplete()
            message.content = "I've prepared a plan for you, but there was an issue with the outline formatting. Let me know if you'd like me to try again."
        }
    }
    
    // Handle checklist events
    private func handleChecklistEvent(eventType: String, eventData: [String: Any]) {
        print("🔍 StreamingChatViewModel.handleChecklistEvent(eventType: \(eventType), eventData: \(eventData))")
        
        switch eventType {
        case "checklist_start":
            // Create a new message for the checklist creation
            let message = StreamingChatMessageFactory.createAssistantMessage()
            message.content = "Creating plan..."
            messages.append(message)
            currentStreamingMessage = message
            
        case "checklist_update":
            // Update the current message with the new item
            if let currentMessage = currentStreamingMessage,
               let date = eventData["date"] as? String,
               let title = eventData["last_item"] as? String {
                currentMessage.content = "Adding \"\(title)\" to \(date)"
            }
            
        case "checklist_complete":
            // Complete the current message
            if let currentMessage = currentStreamingMessage {
                currentMessage.markAsComplete()
                // Keep the last update message as the final content
                
                // Trigger haptic feedback for completion
                hapticGenerator.impactOccurred()
                
                // Reset streaming state
                isStreaming = false
                currentStreamingMessage = nil
                
                // Increment unread count if not expanded
                if !isExpanded {
                    unreadCount += 1
                }
            }
            return
            
        default:
            print("DEBUG CHECKLIST: Unknown checklist event type: \(eventType)")
        }
    }
} 
