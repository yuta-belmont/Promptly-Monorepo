import Foundation
import CoreData
import Firebase
import Network
import SwiftUI

final class ChatService {
    // Replace OpenAI endpoint with our server endpoint
    private let authManager = AuthManager.shared
    private let serverBaseURL = "http://192.168.1.166:8080/api/v1"
    private let persistenceService = ChatPersistenceService.shared
    private let firestoreService = FirestoreService.shared
    
    // This will hold a reference to the ChatViewModel to avoid creating new instances
    private weak var chatViewModel: ChatViewModel?
    
    // Network path monitor for connectivity checking
    private let networkMonitor = NWPathMonitor()
    private var isConnected = true
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    
    // Track the current chat ID on the server
    private var currentChatId: String?
    // Track the current checklist task ID
    private var currentChecklistTaskId: String?
    // Track the current message task ID
    private var currentMessageTaskId: String?
    
    // Callback for message updates
    var onMessageUpdate: ((String) -> Void)?
    
    init() {
        // Set up network path monitor
        networkMonitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
            print("Network connection status changed: \(path.status == .satisfied ? "Connected" : "Disconnected")")
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    // Check if we have an internet connection
    func checkConnectivity() -> Bool {
        return isConnected
    }

    // Method to send a message with additional context
    func sendMessage(messages: [ChatMessage], additionalContext: [[String: Any]]) async throws -> (ChatMessage?, Bool) {
        // Log the message that's about to be sent (usually the last one)
        if let lastMessage = messages.last {
            print("📤 SENDING MESSAGE WITH CONTEXT: \(lastMessage.content)")
            print("📤 MESSAGE SIZE: \(lastMessage.content.utf8.count) bytes")
            print("📤 CONTEXT SIZE: \(additionalContext.count) messages")
        }
        
        // Check for connectivity first
        guard checkConnectivity() else {
            throw NSError(domain: "ChatService", code: -1009, userInfo: [NSLocalizedDescriptionKey: "No internet connection. Please check your network settings and try again."])
        }
        
        guard let token = authManager.getToken() else {
            throw NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Get the last user message
        guard let lastMessage = messages.last(where: { $0.role == MessageRoles.user }) else {
            throw NSError(domain: "ChatService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No user message to send"])
        }
        
        // Use the stateless endpoint directly
        let url = URL(string: "\(serverBaseURL)/chat/messages")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.promptly.optimized+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        
        // Get current date and time
        let currentDate = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = TimeZone.current  // Use the device's local time zone
        let currentTimeString = dateFormatter.string(from: currentDate)
        
        // Create payload with context and current_time
        let payload: [String: Any] = [
            "message": lastMessage.content,
            "context_messages": additionalContext,
            "current_time": currentTimeString
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = bodyData
        
        // Print the size of the outgoing message
        print("📤 OUTGOING MESSAGE SIZE: \(bodyData.count) bytes")
        
        // Print the entire outgoing payload for debugging
        if let payloadString = String(data: bodyData, encoding: .utf8) {
            print("📤 OUTGOING PAYLOAD: \(payloadString)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Print the size of the incoming response
        print("📥 INCOMING RESPONSE SIZE: \(data.count) bytes")
        
        // Log the raw response data
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("RAW SERVER RESPONSE: \(rawResponse)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw NSError(domain: "ChatService", code: (response as? HTTPURLResponse)?.statusCode ?? 400, 
                        userInfo: [NSLocalizedDescriptionKey: "Failed to send message: \(String(data: data, encoding: .utf8) ?? "Unknown error")"])
        }
        
        // Try parsing the optimized response format
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Check for the streamlined format with "response" and optional "metadata"
            if let responseData = json["response"] as? [String: Any] {
                // Check for metadata with message_id
                if let metadata = json["metadata"] as? [String: Any] {
                    if let messageId = metadata["message_id"] as? String {
                        print("MESSAGE DEBUG: Found message_id in metadata: \(messageId)")
                        
                        // Store the task ID
                        self.currentMessageTaskId = messageId
                        
                        // Set up a listener for this message task
                        setupMessageTaskListener(taskId: messageId)
        
        // We no longer create an AI message here since it will come from the Firestore listener
                        // Return nil for the message and false for the flag
                        return (nil, false)
                    }
                }
            }
        }
        
        // If we reach here, something unexpected happened with the response
        print("WARNING: Could not properly parse server response for stateless message")
        throw NSError(domain: "ChatService", code: 400, 
                     userInfo: [NSLocalizedDescriptionKey: "Failed to parse server response"])
    }

    /// Sends a message with context to the server and parses the response.
    /// This is a specialized version of sendMessageToServer that includes context messages.
    private func sendMessageWithContextToServer(
        chatId: String, 
        content: String, 
        contextMessages: [[String: Any]], 
        nextSequence: Int, 
        token: String
    ) async throws -> String {
        let url = URL(string: "\(serverBaseURL)/chat/\(chatId)/messages")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.promptly.optimized+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        
        // Get current date and time
        let currentDate = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = TimeZone.current  // Use the device's local time zone
        let currentTimeString = dateFormatter.string(from: currentDate)
        
        // Create payload with context and current_time instead of next_sequence
        let payload: [String: Any] = [
            "message": content,
            "context_messages": contextMessages,
            "current_time": currentTimeString
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = bodyData
        
        // Print the size of the outgoing message
        print("📤 OUTGOING MESSAGE SIZE: \(bodyData.count) bytes")
        
        // Print the entire outgoing payload for debugging
        if let payloadString = String(data: bodyData, encoding: .utf8) {
            print("📤 OUTGOING PAYLOAD: \(payloadString)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Print the size of the incoming response
        print("📥 INCOMING RESPONSE SIZE: \(data.count) bytes")
        
        // Log the raw response data
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("RAW SERVER RESPONSE: \(rawResponse)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw NSError(domain: "ChatService", code: (response as? HTTPURLResponse)?.statusCode ?? 400, 
                        userInfo: [NSLocalizedDescriptionKey: "Failed to send message: \(String(data: data, encoding: .utf8) ?? "Unknown error")"])
        }
        
        // Try parsing the optimized response format first
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Check for the new streamlined format with "response" and optional "metadata"
            if let responseData = json["response"] as? [String: Any],
               let responseContent = responseData["content"] as? String {
                                
                // Check for metadata with message_id or checklist_id
                if let metadata = json["metadata"] as? [String: Any] {
                    if let messageId = metadata["message_id"] as? String {
                        print("MESSAGE DEBUG: Found message_id in metadata: \(messageId)")
                        
                        // Store the task ID
                        self.currentMessageTaskId = messageId
                        
                        // Set up a listener for this message task
                        setupMessageTaskListener(taskId: messageId)
                        // Return empty string immediately after setting up the listener
                        return ""
                    }
                    else if let checklistId = metadata["checklist_id"] as? String {
                        print("CHECKLIST DEBUG: Found checklist_id in metadata: \(checklistId)")
                        
                        // Store the task ID
                        self.currentChecklistTaskId = checklistId
                        
                        // Set up a listener for this task
                        setupChecklistTaskListener(taskId: checklistId)
                        // Return empty string immediately after setting up the listener
                        return ""
                    }
                    else if let taskId = metadata["task_id"] as? String {
                        // Legacy format - assume it's a message task
                        print("MESSAGE DEBUG: Found task_id in metadata (legacy format): \(taskId)")
                        
                        // Store the task ID
                        self.currentMessageTaskId = taskId
                        
                        // Set up a listener for this message task
                        setupMessageTaskListener(taskId: taskId)
                        // Return empty string immediately after setting up the listener
                        return ""
                    }
                }
                
                // Return placeholder content for display purposes only
                // The actual content will come from the Firestore listener
                // Instead of returning the content directly, return an empty string to avoid displaying placeholders
                return ""
            }
        }
        
        // If we reach here, either the response wasn't in the optimized format,
        // or it didn't contain the expected fields, or we couldn't parse it properly.
        // In any case, return an empty string and log a warning
        print("WARNING: Could not properly parse server response for message with context")
        return ""
    }
    
    private func createNewChat(token: String) async throws -> String {
        let url = URL(string: "\(serverBaseURL)/chat/")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15 // 15 second timeout for request
        
        let body: [String: Any] = [
            "title": "Mobile Chat \(Date())"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw NSError(domain: "ChatService", code: (response as? HTTPURLResponse)?.statusCode ?? 400, 
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create chat: \(String(data: data, encoding: .utf8) ?? "Unknown error")"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chatId = json["id"] as? String else {
            throw NSError(domain: "ChatService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        return chatId
    }
    
    /// Sends a message to the server and parses the response.
    /// 
    /// This method supports two response formats:
    /// 
    /// 1. Optimized format (preferred):
    /// ```
    /// {
    ///   "response": {
    ///     "id": "message-id",
    ///     "content": "Hello, how can I help you?"
    ///   },
    ///   "metadata": {
    ///     "checklist_task_id": "optional-task-id" // Only present for checklist requests
    ///   }
    /// }
    /// ```
    /// 
    /// 2. Legacy format (fallback):
    /// ```
    /// {
    ///   "id": "chat-id",
    ///   "title": "Chat title",
    ///   "messages": [
    ///     { "role": "user", "content": "User message", ... },
    ///     { "role": "assistant", "content": "Assistant response", ... }
    ///   ]
    /// }
    /// ```
    /// 
    /// - Parameters:
    ///   - chatId: The ID of the chat session
    ///   - content: The user's message content
    ///   - token: The authentication token
    /// - Returns: The assistant's response message content
    private func sendMessageToServer(chatId: String, content: String, token: String) async throws -> String {
        let url = URL(string: "\(serverBaseURL)/chat/\(chatId)/messages")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        // Set an Accept header to indicate preference for the optimized response format
        // If server supports content negotiation, it can return the optimized format
        request.setValue("application/vnd.promptly.optimized+json", forHTTPHeaderField: "Accept")
        
        request.timeoutInterval = 15 // 15 second timeout for request
        
        // We don't need to specify sequence as the server will handle that
        let body: [String: Any] = [
            "content": content
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData
        
        // Print the size of the outgoing message
        print("📤 OUTGOING MESSAGE SIZE: \(bodyData.count) bytes")
        
        // Print the entire outgoing payload for debugging
        if let payloadString = String(data: bodyData, encoding: .utf8) {
            print("📤 OUTGOING PAYLOAD: \(payloadString)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Print the size of the incoming response
        print("📥 INCOMING RESPONSE SIZE: \(data.count) bytes")
        
        // Log the raw response data
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("RAW SERVER RESPONSE: \(rawResponse)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw NSError(domain: "ChatService", code: (response as? HTTPURLResponse)?.statusCode ?? 400, 
                          userInfo: [NSLocalizedDescriptionKey: "Failed to send message: \(String(data: data, encoding: .utf8) ?? "Unknown error")"])
        }
        
        // Try parsing the optimized response format first
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Check for the new streamlined format with "response" and optional "metadata"
            if let responseData = json["response"] as? [String: Any],
               let responseContent = responseData["content"] as? String {
                
                print("📥 ASSISTANT MESSAGE SIZE: \(responseContent.utf8.count) bytes")
                
                // The optimized format eliminates redundant data like:
                // - The user's message which we already have
                // - Chat metadata (title, is_active, etc.)
                // - Timestamps and sequence numbers
                // This can reduce payload size by 70-80% in most cases
                
                // Check for metadata with message_id or checklist_id
                if let metadata = json["metadata"] as? [String: Any] {
                    if let messageId = metadata["message_id"] as? String {
                        print("MESSAGE DEBUG: Found message_id in metadata: \(messageId)")
                        
                        // Set up a listener for this message task
                        setupMessageTaskListener(taskId: messageId)
                        // Return empty string immediately after setting up the listener
                        return ""
                    }
                    else if let checklistId = metadata["checklist_id"] as? String {
                        print("CHECKLIST DEBUG: Found checklist_id in metadata: \(checklistId)")
                        
                        // Store the task ID
                        self.currentChecklistTaskId = checklistId
                        
                        // Set up a listener for this task
                        setupChecklistTaskListener(taskId: checklistId)
                        // Return empty string immediately after setting up the listener
                        return ""
                    }
                    else if let taskId = metadata["task_id"] as? String {
                        // Legacy format - assume it's a message task
                        print("MESSAGE DEBUG: Found task_id in metadata (legacy format): \(taskId)")
                        
                        // Set up a listener for this message task
                        setupMessageTaskListener(taskId: taskId)
                        // Return empty string immediately after setting up the listener
                        return ""
                    }
                }
                
                // Return placeholder content for display purposes only
                // The actual content will come from the Firestore listener
                // Instead of returning the content directly, return an empty string to avoid displaying placeholders
                return ""
            }
        }
        
        // If we reach here, it means we need to fall back to the old format
        print("FALLING BACK TO LEGACY RESPONSE FORMAT")
        
        // Parse the response to get the assistant's message (legacy format)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            throw NSError(domain: "ChatService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        // Find the assistant's message (should be the last one)
        if let assistantMessage = messages.last(where: { ($0["role"] as? String) == "assistant" }),
           let content = assistantMessage["content"] as? String {
            
            print("ASSISTANT MESSAGE CONTENT (PRE-PARSING): \(content)")
            
            // Print the size of the assistant message content
            print("📥 ASSISTANT MESSAGE SIZE: \(content.utf8.count) bytes")
            
            // Check if the response is structured as JSON with a flag
            if let data = content.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let messageContent = json["message"] as? String {
                
                print("PARSED JSON FROM CONTENT: \(json)")
                
                // Check if the response includes task info
                if let taskInfo = json["task_info"] as? [String: Any] {
                    print("Found task_info in response: \(taskInfo)")
                    
                    // Check for checklist task ID
                    if let checklistTaskId = taskInfo["checklist_task_id"] as? String {
                        print("CHECKLIST DEBUG: Found checklist_task_id: \(checklistTaskId)")
                        
                        // Store the task ID
                        self.currentChecklistTaskId = checklistTaskId
                        
                        // Set up a listener for this task
                        setupChecklistTaskListener(taskId: checklistTaskId)
                        
                        print("Set up listener for checklist task: \(checklistTaskId)")
                    } else {
                        print("CHECKLIST DEBUG: No checklist_task_id found in task_info")
                    }
                } else {
                    // Check if task IDs are directly in the message JSON
                    if let checklistTaskId = json["checklist_task_id"] as? String {
                        print("CHECKLIST DEBUG: Found checklist_task_id in message JSON: \(checklistTaskId)")
                        
                        // Store the task ID
                        self.currentChecklistTaskId = checklistTaskId
                        
                        // Set up a listener for this task
                        setupChecklistTaskListener(taskId: checklistTaskId)
                        
                        print("Set up listener for checklist task from message JSON: \(checklistTaskId)")
                    }
                }
                
                // Return just the message content, not the whole JSON
                return messageContent
            }
            
            return content
        }
        
        throw NSError(domain: "ChatService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No assistant message found in response"])
    }
    
    private func parseChecklist(from text: String) -> [Models.ChecklistItem]? {
        print("CHECKLIST DEBUG: Attempting to parse checklist from: \(text)")
        
        // Try to parse as JSON first
        if let data = text.data(using: .utf8) {
            do {
                // Try to parse as JSON
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("CHECKLIST DEBUG: Successfully parsed text as JSON")
                    
                    // Check if this is our structured response format
                    if let message = json["message"] as? String,
                       let checklists = json["checklists"] as? [String: [String: Any]] {
                        
                        print("CHECKLIST DEBUG: Found structured checklist format with message and checklists")
                        var allItems: [Models.ChecklistItem] = []
                        
                        // Process each checklist
                        for (dateKey, checklistData) in checklists {
                            // Parse the date from the key
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd"
                            if let date = dateFormatter.date(from: dateKey),
                               let items = checklistData["items"] as? [[String: Any]] {
                                
                                print("CHECKLIST DEBUG: Processing checklist for date: \(dateKey) with \(items.count) items")
                                
                                // Process each item in the checklist
                                for itemData in items {
                                    if let title = itemData["title"] as? String {
                                        // Parse notification time if present
                                        var notificationDate: Date? = nil
                                        if let notificationTime = itemData["notification"] as? String, notificationTime != "null" {
                                            // Combine the date with the time
                                            let timeFormatter = DateFormatter()
                                            timeFormatter.dateFormat = "HH:mm"
                                            if let time = timeFormatter.date(from: notificationTime) {
                                                let calendar = Calendar.current
                                                let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
                                                notificationDate = calendar.date(bySettingHour: timeComponents.hour ?? 0, 
                                                                                minute: timeComponents.minute ?? 0, 
                                                                                second: 0, 
                                                                                of: date)
                                            }
                                        }
                                        
                                        // Create the checklist item
                                        allItems.append(Models.ChecklistItem(
                                            title: title,
                                            date: date,
                                            isCompleted: false,
                                            notification: notificationDate,
                                            group: nil
                                        ))
                                        
                                        print("CHECKLIST DEBUG: Added item: \(title)")
                                    }
                                }
                            }
                        }
                        
                        if !allItems.isEmpty {
                            print("CHECKLIST DEBUG: Successfully parsed \(allItems.count) checklist items")
                            return allItems
                        } else {
                            print("CHECKLIST DEBUG: No checklist items found in structured format")
                        }
                    } else {
                        print("CHECKLIST DEBUG: JSON does not contain expected 'message' and 'checklists' fields")
                    }
                }
            } catch {
                print("CHECKLIST DEBUG: Error parsing JSON: \(error)")
            }
        }
        
        print("CHECKLIST DEBUG: Falling back to text parsing")
        
        // Fallback to the original text parsing if JSON parsing fails
        let lines = text.components(separatedBy: "\n")
        var checklistItems: [Models.ChecklistItem] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.range(of: #"^\d+\."#, options: .regularExpression) != nil {
                let taskText = trimmed.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
                checklistItems.append(Models.ChecklistItem(
                    title: String(taskText), 
                    date: Date(),
                    isCompleted: false,
                    notification: nil,
                    group: nil
                ))
                
                print("CHECKLIST DEBUG: Added item from text parsing: \(taskText)")
            }
        }
        
        if checklistItems.isEmpty {
            print("CHECKLIST DEBUG: No checklist items found in text format")
            return nil
        } else {
            print("CHECKLIST DEBUG: Successfully parsed \(checklistItems.count) checklist items from text")
            return checklistItems
        }
    }
    
    // MARK: - Firestore Listeners
    
    /// Set up a real-time listener for a message task
    /// - Parameter taskId: The task ID to listen for
    private func setupMessageTaskListener(taskId: String) {
        // First ensure we have Firebase authentication
        Task {
            guard await authManager.ensureFirebaseAuth() else {
                print("MESSAGE DEBUG: Cannot set up listener - no Firebase authentication")
                return
            }
            
            // Use the enhanced FirestoreService which now tracks active listeners
            // The method will return false if a listener is already active for this task ID
            let listenerSetup = firestoreService.listenForMessageTask(taskId: taskId) { [weak self] status, data in
                guard let self = self else { return }
                
                
                if status == "completed", let data = data {
                    
                    // Update loading indicator based on listener status
                    // This will automatically hide if no listeners are active
                    Task { @MainActor in
                        self.chatViewModel?.updateLoadingIndicator()
                    }
                    
                    // Check for response field, which contains the message content
                    if let response = data["response"] as? String {
                        
                        // Create a new message in the chat UI
                        Task { @MainActor in
                            self.addAssistantMessage(response)
                        }
                        
                        // Check if this message task generated a checklist task
                        if let checklistTaskId = data["checklist_task_id"] as? String {
                            // Set up a listener for the checklist task
                            self.setupChecklistTaskListener(taskId: checklistTaskId)
                        }
                    }
                    
                    // Listener cleanup is now handled by FirestoreService automatically
                    // when task status is completed or failed
                } else if status == "failed" {
                    
                    // Update loading indicator based on listener status
                    // This will automatically hide if no listeners are active
                    Task { @MainActor in
                        self.chatViewModel?.updateLoadingIndicator()
                    }
                    
                    // If we have error details, show them to the user
                    let errorDetails = (data?["error"] as? String) ?? "Unknown error"
                    
                    // Add an error message to the chat
                    Task { @MainActor in
                        self.addAssistantMessage("Sorry, I encountered an error: \(errorDetails)")
                    }
                    
                    // Listener cleanup is now handled by FirestoreService automatically
                }
            }
            
            if listenerSetup {
                // Only update our local tracking if a new listener was actually set up
                currentMessageTaskId = taskId
                
                // Update the loading indicator since we just set up a listener
                Task { @MainActor in
                    self.chatViewModel?.updateLoadingIndicator()
                }
            }
        }
    }
    
    /// Set up a real-time listener for a checklist task
    /// - Parameter taskId: The task ID to listen for
    private func setupChecklistTaskListener(taskId: String) {
        
        // First ensure we have Firebase authentication
        Task {
            guard await authManager.ensureFirebaseAuth() else {
                print("CHECKLIST DEBUG: Cannot set up listener - no Firebase authentication")
                return
            }
            
            // Use the enhanced FirestoreService which now tracks active listeners
            // The method will return false if a listener is already active for this task ID
            let listenerSetup = firestoreService.listenForChecklistTask(taskId: taskId) { [weak self] status, data in
                guard let self = self else { return }
                
                if status == "completed", let data = data {
                    
                    // Update loading indicator based on listener status
                    // This will automatically hide if no listeners are active
                    Task { @MainActor in
                        self.chatViewModel?.updateLoadingIndicator()
                    }
                    
                    
                    // Check for checklist_data field, which contains the structured checklist
                    if let checklistData = data["checklist_data"] as? [String: Any] {
                        
                        // Print the size of the checklist data
                        if let checklistJSON = try? JSONSerialization.data(withJSONObject: checklistData) {
                            print("📥 CHECKLIST DATA SIZE: \(checklistJSON.count) bytes")
                        }
                        
                        // Convert the Firebase checklist data to our app's model
                        if let modelChecklists = self.convertFirebaseChecklistToModel(checklistData: checklistData) {
                            
                            // Save the checklists to persistence
                            Task { @MainActor in
                                self.saveOrAppendChecklists(modelChecklists)
                            }
                        } else {
                            
                            // Provide an error message
                            let errorMessage = """
                            {"message": "Failed to create checklist. The data format was unexpected."}
                            """
                            self.onMessageUpdate?(errorMessage)
                            
                            // Add a simple error message after a short delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                Task { @MainActor in
                                    // First send the detailed error through the callback for immediate display
                                    self.onMessageUpdate?(errorMessage)
                                    
                                    // Then add the simple error message properly to chat history
                                    self.addAssistantMessage("Sorry, some kind of error occurred.")
                                }
                            }
                        }
                    } else {
                        print("CHECKLIST DEBUG: No checklist_data or generated_content found in task data")
                        let errorMessage = """
                        {"message": "Failed to create checklist. No data was received from the server."}
                        """
                        self.onMessageUpdate?(errorMessage)
                        
                        // Add a simple error message after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            Task { @MainActor in
                                // First send the detailed error through the callback for immediate display
                                self.onMessageUpdate?(errorMessage)
                                
                                // Then add the simple error message properly to chat history
                                self.addAssistantMessage("Sorry, some kind of error occurred.")
                            }
                        }
                    }
                    
                    // Listener cleanup is now handled by FirestoreService automatically
                    // when task status is completed or failed
                } else if status == "failed" {
                    print("CHECKLIST DEBUG: Checklist task failed")
                    
                    // Update loading indicator based on listener status
                    // This will automatically hide if no listeners are active
                    Task { @MainActor in
                        self.chatViewModel?.updateLoadingIndicator()
                    }
                    
                    // If we have error details, show them to the user
                    let errorDetails = (data?["error"] as? String) ?? "Unknown error"
                    let errorMessage = """
                    {"message": "Failed to create checklist: \(errorDetails)"}
                    """
                    
                    DispatchQueue.main.async {
                        self.onMessageUpdate?(errorMessage)
                        
                        // Add a simple error message after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            Task { @MainActor in
                                // First send the detailed error through the callback for immediate display
                                self.onMessageUpdate?(errorMessage)
                                
                                // Then add the simple error message properly to chat history
                                self.addAssistantMessage("Sorry, some kind of error occurred.")
                            }
                        }
                    }
                    
                    // Listener cleanup is now handled by FirestoreService automatically
                }
            }
            
            if listenerSetup {
                // Only update our local tracking if a new listener was actually set up
                currentChecklistTaskId = taskId
                
                // Update the loading indicator since we just set up a listener
                Task { @MainActor in
                    self.chatViewModel?.updateLoadingIndicator()
                }
            }
        }
    }
    
    // Helper method to format a date for display
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    /// Clean up all listeners when the service is no longer needed
    func cleanup() {
        // No need to manually remove specific listeners - just use the FirestoreService method
        firestoreService.removeAllMessageListeners()
        
        // Reset our task ID tracking
        currentMessageTaskId = nil
        currentChecklistTaskId = nil
    }

    // MARK: - Firebase Checklist Conversion

    /// Converts a Firebase checklist JSON structure to a local model Checklist
    /// - Parameter checklistData: The raw checklist data from Firebase
    /// - Returns: A Models.Checklist object or nil if the data can't be parsed
    func convertFirebaseChecklistToModel(checklistData: [String: Any]) -> [Models.Checklist]? {
        print("CHECKLIST DEBUG: Converting Firebase checklist data to model: \(checklistData)")
        
        // Our example structure:
        // ["2025-03-17": {
        //     items =     (
        //               {
        //             notification = "15:00";
        //             title = "Write down your top goal for the week and break it into actionable steps";
        //         }
        //     );
        //     notes = "Focus on setting a clear intention for the day. Remember: 'Well begun is half done.' Use this opportunity to start the week off strong and make meaningful progress.";
        // }]
        
        // Verify we have data to process
        guard !checklistData.isEmpty else {
            print("CHECKLIST DEBUG: Empty checklist data received")
            return nil
        }
        
        // Create an array to hold all checklists
        var allChecklists: [Models.Checklist] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        // Process each date in the checklist data
        for (dateString, checklistInfo) in checklistData {
            // Skip any keys that aren't date strings
            guard dateFormatter.date(from: dateString) != nil,
                  let checklistInfo = checklistInfo as? [String: Any] else {
                print("CHECKLIST DEBUG: Skipping non-date key or invalid format: \(dateString)")
                continue
            }
            
            // Parse the date
            guard let date = dateFormatter.date(from: dateString) else {
                print("CHECKLIST DEBUG: Failed to parse date: \(dateString)")
                continue
            }
            
            // Get the notes from the checklist
            let notes = (checklistInfo["notes"] as? String) ?? ""
            
            // Parse the items array
            var checklistItems: [Models.ChecklistItem] = []
            if let items = checklistInfo["items"] as? [[String: Any]] {
                for itemData in items {
                    if let title = itemData["title"] as? String {
                        // Parse notification time if present
                        var notificationDate: Date? = nil
                        if let notificationTime = itemData["notification"] as? String, notificationTime != "null" {
                            print("CHECKLIST DEBUG: Processing notification time: \(notificationTime)")
                            // Combine the date with the time
                            let timeFormatter = DateFormatter()
                            timeFormatter.dateFormat = "HH:mm"
                            if let time = timeFormatter.date(from: notificationTime) {
                                let calendar = Calendar.current
                                let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
                                let hour = timeComponents.hour ?? 0
                                let minute = timeComponents.minute ?? 0
                                
                                notificationDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
                                
                                print("CHECKLIST DEBUG: Parsed time \(notificationTime) to components - hour: \(hour), minute: \(minute)")
                                print("CHECKLIST DEBUG: Created notification date: \(notificationDate?.description ?? "nil")")
                            } else {
                                print("CHECKLIST DEBUG: Failed to parse time format: \(notificationTime)")
                            }
                        }
                        
                        // Create the checklist item
                        checklistItems.append(Models.ChecklistItem(
                            title: title,
                            date: date,
                            isCompleted: false,
                            notification: notificationDate,
                            group: nil
                        ))
                        
                        print("CHECKLIST DEBUG: Added item: \(title)")
                    }
                }
            }
            
            // Create and add the checklist
            let checklist = Models.Checklist(
                id: UUID(),
                date: date,
                items: checklistItems,
                notes: notes
            )
            
            allChecklists.append(checklist)
            print("CHECKLIST DEBUG: Created checklist for \(dateString) with \(checklistItems.count) items and notes: \(notes)")
        }
        
        print("CHECKLIST DEBUG: Processed \(allChecklists.count) checklists in total")
        return allChecklists.isEmpty ? nil : allChecklists
    }

    // MARK: - Adding Messages to Chat
    
    /// Add a simple text message from the assistant to the chat
    /// This method follows the exact same pattern as ChatViewModel.addMessageAndNotify:
    /// 1. Creates a proper ChatMessage entity using ChatMessage.create
    /// 2. Adds it to the main chat history
    /// 3. Saves the chat history through the persistence service
    /// 4. Posts a notification via NotificationCenter to update the UI
    /// This ensures messages appear properly in the chat interface and are persisted in Core Data
    @MainActor
    private func addAssistantMessage(_ message: String) {
        let context = persistenceService.viewContext
        
        // Log the message being added to chat history
        print("💬 ADDING MESSAGE TO CHAT: \(message)")
        print("💬 CHAT MESSAGE SIZE: \(message.utf8.count) bytes")
        
        // Create a new message entity using the proper ChatMessage.create method
        let chatMessage = ChatMessage.create(
            in: context,
            role: MessageRoles.assistant,
            content: message
        )
        
        // Get the main chat history
        Task {
            if let mainHistory = await persistenceService.loadMainChatHistory() {
                // Add message to history
                mainHistory.addMessage(chatMessage)
                
                // Save the chat history
                persistenceService.saveChatHistory(mainHistory)
                
                // Notify that a message was added
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name("ChatMessageAdded"),
                        object: nil,
                        userInfo: [
                            "role": MessageRoles.assistant
                        ]
                    )
                }
            } else {
                // Create a new main chat history if it doesn't exist
                let newHistory = ChatHistory.create(in: context, isMainHistory: true)
                newHistory.addMessage(chatMessage)
                persistenceService.saveChatHistory(newHistory)
                
                // Notify that a message was added
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name("ChatMessageAdded"),
                        object: nil,
                        userInfo: [
                            "role": MessageRoles.assistant
                        ]
                    )
                }
            }
            
            // Also send the message through the callback for real-time updates
            self.onMessageUpdate?("""
            {"message": "\(message)"}
            """)
        }
    }

    @MainActor
    private func saveOrAppendChecklists(_ checklists: [Models.Checklist]) {
        let persistence = ChecklistPersistence.shared
        var updatedDates: [Date] = []
        var totalItemsAdded = 0
        
        for checklist in checklists {
            // Check if a checklist already exists for this date
            if let existingChecklist = persistence.loadChecklist(for: checklist.date) {
                print("CHECKLIST DEBUG: Found existing checklist for date: \(checklist.date)")
                
                // Create an updated checklist by appending the new items
                var updatedChecklist = existingChecklist
                updatedChecklist.items.append(contentsOf: checklist.items)
                totalItemsAdded += checklist.items.count
                
                // Update notes if the new checklist has notes
                if !checklist.notes.isEmpty {
                    if !updatedChecklist.notes.isEmpty {
                        updatedChecklist.notes += "\n\n" + checklist.notes
                    } else {
                        updatedChecklist.notes = checklist.notes
                    }
                }
                
                // Save the updated checklist
                persistence.saveChecklist(updatedChecklist)
                print("CHECKLIST DEBUG: Updated existing checklist for date: \(checklist.date), now with \(updatedChecklist.items.count) items")
                
                updatedDates.append(checklist.date)
            } else {
                // No existing checklist, save the new one
                persistence.saveChecklist(checklist)
                totalItemsAdded += checklist.items.count
                print("CHECKLIST DEBUG: Saved new checklist to persistence for date: \(checklist.date)")
                
                updatedDates.append(checklist.date)
            }
            
            // Notify the UI that a checklist was updated
            NotificationCenter.default.post(name: Notification.Name("NewChecklistAvailable"), object: checklist.date)
        }
        
        // Sort dates to display them in order
        let sortedDates = updatedDates.sorted()
        
        // Format the dates for the message
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        let formattedDates: [String] = sortedDates.map { formatter.string(from: $0) }
        
        // Create a user-friendly message
        let message: String
        if formattedDates.count == 1 {
            message = "Added \(totalItemsAdded) item\(totalItemsAdded == 1 ? "" : "s") to your checklist for \(formattedDates[0])."
        } else if formattedDates.count <= 3 {
            let datesText = formattedDates.joined(separator: ", ")
            message = "Added items to your checklists for \(datesText)."
        } else {
            message = "Added items to \(formattedDates.count) different dates in your calendar."
        }
        
        // Send the detailed message using the onMessageUpdate callback
        self.onMessageUpdate?("""
        {"message": "\(message)"}
        """)
        
        // After a short delay, add the simple "Done." message properly to the chat
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { @MainActor in
                // Properly add the confirmation message to chat history
                self.addAssistantMessage("Done.")
            }
        }
    }

    // Add method to set the ChatViewModel
    func setChatViewModel(_ viewModel: ChatViewModel) {
        self.chatViewModel = viewModel
    }
}

// MARK: - Server API Response Models

struct ChatResponse: Codable {
    let id: String
    let title: String
    let messages: [MessageResponse]?
}

struct MessageResponse: Codable {
    let id: String
    let role: String
    let content: String
    let sequence: Int
}

